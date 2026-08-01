import paho.mqtt.client as mqtt
import json
import time
import math
import serial
import smbus

I2C_BUS = 1
MPU_ADDR = 0x68

SERIAL_PORT = "/dev/ttyAMA0"
BAUD = 115200

EMERGENCY_NUMBERS = ["+xxxxxxxxxxxx"]

USER_NAME = "User"

IMPACT_G = 2.0
FREEFALL_G = 0.1
FREEFALL_MS = 10
COOLDOWN_S = 10
GPS_TIMEOUT = 7

GYRO_THRESHOLD = 200

MQTT_BROKER = "127.0.0.1"
MQTT_PORT = 1883

CONFIG_FILE = "resqnet_config.json"

def load_config():
    global EMERGENCY_NUMBERS
    try:
        with open(CONFIG_FILE, 'r') as f:
            config = json.load(f)
            if 'emergency_numbers' in config and isinstance(config['emergency_numbers'], list):
                EMERGENCY_NUMBERS = config['emergency_numbers']
                print(f"[*] Loaded saved emergency numbers: {EMERGENCY_NUMBERS}")
            else:
                save_config()
    except Exception as e:
        print(f"[*] No config file found or error loading, saving default number list. {e}")
        save_config()

def save_config():
    global EMERGENCY_NUMBERS
    try:
        with open(CONFIG_FILE, 'w') as f:
            json.dump({'emergency_numbers': EMERGENCY_NUMBERS}, f)
            print(f"[*] Config saved: {EMERGENCY_NUMBERS}")
    except Exception as e:
        print(f"[!] Error saving config: {e}")

def on_message(client, userdata, msg):
    global EMERGENCY_NUMBERS

    if msg.topic == "resqnet/config/number":
        try:
            raw_string = msg.payload.decode('utf-8')

            new_list = [num.strip() for num in raw_string.split(',') if num.strip()]

            if new_list:
                EMERGENCY_NUMBERS = new_list
                print(f"[MQTT] Updated emergency numbers to: {EMERGENCY_NUMBERS}")
                save_config()
            else:
                print("[MQTT] Received empty number list, not updating.")

        except Exception as e:
            print(f"[!] Error processing MQTT message: {e}")

def on_connect(client, userdata, flags, rc):
    print(f"[*] Connected to MQTT with result code {rc}")
    client.subscribe("resqnet/config/number")


mqtt_client = mqtt.Client()
mqtt_client.on_connect = on_connect
mqtt_client.on_message = on_message
mqtt_client.connect(MQTT_BROKER, MQTT_PORT, 60)
mqtt_client.loop_start()

FALLBACK_LINK = "https://maps.google.com/?q=18.592376,73.801730"

bus = smbus.SMBus(I2C_BUS)

def init_mpu():
    try:
        bus.write_byte_data(MPU_ADDR, 0x6B, 0x00)
        time.sleep(0.1)
    except Exception as e:
        print("[!] init_mpu error:", e)

init_mpu()

def read_word(reg):
    high = bus.read_byte_data(MPU_ADDR, reg)
    low  = bus.read_byte_data(MPU_ADDR, reg+1)

    val = (high << 8) | low

    if val >= 0x8000:
        val = -((65535 - val) + 1)
    return val

def get_accel():
    ax = read_word(0x3B) / 16384.0
    ay = read_word(0x3D) / 16384.0
    az = read_word(0x3F) / 16384.0
    return ax, ay, az

def accel_mag():
    ax, ay, az = get_accel()
    return math.sqrt(ax*ax + ay*ay + az*az)

def safe_accel_mag():
    try:
        return accel_mag()
    except Exception:
        init_mpu()
        time.sleep(0.05)
        try:
            return accel_mag()
        except Exception:
            return None

def get_gyro():
    gx = read_word(0x43) / 131.0
    gy = read_word(0x45) / 131.0
    gz = read_word(0x47) / 131.0
    return gx, gy, gz

def gyro_mag():
    gx, gy, gz = get_gyro()
    return math.sqrt(gx*gx + gy*gy + gz*gz)

def safe_gyro_mag():
    try:
        return gyro_mag()
    except Exception:
        init_mpu()
        time.sleep(0.05)
        try:
            return gyro_mag()
        except Exception:
            return None

try:
    ser = serial.Serial(SERIAL_PORT, BAUD, timeout=1)
    time.sleep(0.2)
except Exception as e:
    print("[!] Serial open error:", e)
    ser = None

def at(cmd, delay=0.5):
    if ser is None:
        return ""
    ser.write((cmd + "\r\n").encode())
    time.sleep(delay)
    return ser.read(ser.in_waiting).decode(errors="ignore")

def get_gps_info():
    if ser is None:
        return None

    at("AT+CGPS=1")
    start = time.time()

    while time.time() - start < GPS_TIMEOUT:
        r = at("AT+CGPSINFO", 1)
        if "+CGPSINFO:" in r:
            parts = r.split(":")[1].strip().split(",")

            try:
                lat, lat_dir, lon, lon_dir = parts[0], parts[1], parts[2], parts[3]
            except Exception:
                lat = lon = ""
                lat_dir = lon_dir = ""

            if lat != "" and lon != "":
                try:
                    def conv(v, d):
                        base = v.split('.')[0]
                        if len(base) > 4:
                            deg = float(v[:3])
                            mins = float(v[3:])
                        else:
                            deg = float(v[:2])
                            mins = float(v[2:])
                        dec = deg + mins/60
                        return -dec if d in ["S", "W"] else dec

                    return conv(lat, lat_dir), conv(lon, lon_dir)
                except Exception:
                    pass

        time.sleep(1)

    return None

def send_sms(number, text):
    if ser is None:
        print("[!] Cannot send SMS: serial not available")
        return ""
    at("AT+CMGF=1")
    at(f'AT+CMGS="{number}"')
    ser.write((text + "\x1A").encode())
    time.sleep(3)
    return ser.read(ser.in_waiting).decode(errors="ignore")

def _dial_one_number(number):
    if ser is None:
        print(f"[!] Cannot call {number}: serial not available")
        return
    try:
        print(f"[*] Calling {number}...")
        ser.write((f"ATD{number};\r\n").encode())
        time.sleep(2)
        timeout = time.time() + 15
        while time.time() < timeout:
            if ser.in_waiting:
                ser.read(ser.in_waiting)
            time.sleep(0.1)
        print(f"[*] Hanging up call with {number}")
        ser.write(b"ATH\r\n")
        time.sleep(1)
    except Exception as e:
        print(f"[!] Call to {number} error: {e}")

def call_all_numbers():
    global EMERGENCY_NUMBERS
    if not EMERGENCY_NUMBERS:
        print("[!] No emergency numbers configured to call.")
        return

    print(f"[*] Starting call sequence for {len(EMERGENCY_NUMBERS)} number(s)...")
    for number in EMERGENCY_NUMBERS:
        _dial_one_number(number)
        time.sleep(1)
    print("[*] Call sequence finished.")


def fallback_coords():
    try:
        q = FALLBACK_LINK.split("?q=")[1]
        lat_s, lon_s = q.split(",")
        return float(lat_s), float(lon_s)
    except Exception:
        return 0.0, 0.0

def publish_crash_event(lat, lon, reason, impact_g):
    if impact_g < 1.5:
        severity = "low"
    elif impact_g < 3.0:
        severity = "medium"
    else:
        severity = "severe"

    data = {
        "type": "crash",
        "lat": lat,
        "lon": lon,
        "reason": reason,
        "impact_g": impact_g,
        "severity": severity,
        "timestamp": time.time()
    }
    mqtt_client.publish("resqnet/crash", json.dumps(data))
    print("[MQTT] Published crash event with severity:", severity)

def publish_location(lat, lon):
    data = {"lat": lat, "lon": lon}
    mqtt_client.publish("resqnet/location", json.dumps(data))


load_config()
print("[*] Crash detection started...")

last_trigger = 0
freefall_start = None

while True:
    mag = safe_accel_mag()
    gyro = safe_gyro_mag()

    if mag is None or gyro is None:
        time.sleep(0.01)
        continue

    if mag < FREEFALL_G:
        if freefall_start is None:
            freefall_start = time.time()
    else:
        if freefall_start:
            dur = (time.time() - freefall_start) * 1000.0
            freefall_start = None

            if dur >= FREEFALL_MS:
                print(f"[!] FREEFALL detected for {dur:.1f} ms")

                impact = False
                end = time.time() + 0.4

                while time.time() < end:
                    mag2 = safe_accel_mag()
                    gyro2 = safe_gyro_mag()

                    if (mag2 is not None and mag2 > IMPACT_G) or (gyro2 is not None and gyro2 > GYRO_THRESHOLD):
                        impact = True
                        break

                    time.sleep(0.002)

                if impact and time.time() - last_trigger > COOLDOWN_S:
                    last_trigger = time.time()
                    print("[!] CRASH DETECTED (freefall + impact/gyro)")
                    print("[*] Getting GPS...")
                    gps = get_gps_info()
                    if gps:
                        lat, lon = gps
                        print(f"[*] GPS result: ({lat:.6f}, {lon:.6f})")
                    else:
                        lat, lon = fallback_coords()
                        print(f"[*] GPS result: ({lat:.6f}, {lon:.6f}) [fallback]")

                    link = f"https://maps.google.com/?q={lat},{lon}"
                    publish_crash_event(lat, lon, "freefall+impact", mag2)
                    sms = f"ALERT: Crash detected for {USER_NAME}.\nLocation: {link}"

                    print("[*] Sending SMS to all numbers...")
                    for num in EMERGENCY_NUMBERS:
                        print(send_sms(num, sms))

                    print("[*] Calling emergency numbers...")

                    try:
                        call_all_numbers()
                    except Exception as e:
                        print("[!] Call exception:", e)

    if (mag is not None and mag > IMPACT_G) or (gyro is not None and gyro > GYRO_THRESHOLD):
        if time.time() - last_trigger > COOLDOWN_S:
            last_trigger = time.time()

            reason = []
            if mag is not None and mag > IMPACT_G:
                reason.append(f"impact (G={mag:.3f})")
            if gyro is not None and gyro > GYRO_THRESHOLD:
                reason.append(f"gyro (deg/s={gyro:.1f})")

            print(f"[!] CRASH DETECTED ({' + '.join(reason)})")

            print("[*] Getting GPS...")
            gps = get_gps_info()
            if gps:
                lat, lon = gps
                print(f"[*] GPS result: ({lat:.6f}, {lon:.6f})")
            else:
                lat, lon = fallback_coords()
                print(f"[*] GPS result: ({lat:.6f}, {lon:.6f}) [fallback]")

            link = f"https://maps.google.com/?q={lat},{lon}"
            publish_crash_event(lat, lon, "impact/gyro", mag)
            sms = f"ALERT: Crash detected for {USER_NAME}.\nLocation: {link}"

            print("[*] Sending SMS to all numbers...")
            for num in EMERGENCY_NUMBERS:
                print(send_sms(num, sms))

            print("[*] Calling emergency numbers...")
            try:
                call_all_numbers()
            except Exception as e:
                print("[!] Call exception:", e)

    time.sleep(0.005)
