# ResQnet: Crash Detection and Notification System

**Patent-pending** IoT system that automatically detects vehicle accidents and alerts emergency contacts within seconds - no human action required.

> Application No. 202521090608 (filed with the Government of India)

---

## The Problem

- Over **1.5 lakh people** die every year in road accidents in India (Ministry of Road Transport and Highways), and roughly **40% of those deaths** occur due to delays in medical attention.
- Globally, the WHO estimates **1.35 million deaths** per year from road crashes.
- In many accidents, victims are unconscious, trapped, or otherwise unable to call for help - and every minute of delay lowers survival odds.

ResQnet removes the dependency on the victim (or a bystander) to raise the alarm. The system detects the crash itself and dispatches help automatically.

---

## How It Works

```
[MPU-9255 motion sensor] → [Raspberry Pi 5] → [SIM7600 G-H module] → Call / SMS / GPS
                                   |
                                   └──(MQTT)──→ [Flutter app] → Push notification + live map
```

1. An **MPU-9255** high-precision motion sensor continuously monitors the vehicle's acceleration and orientation.
2. A **Raspberry Pi 5** processes this data in real time and identifies sudden impacts consistent with a crash.
3. On detecting a significant impact, the Pi triggers a **SIM7600 G-H** communication module, which:
   - Places a call to the registered emergency contact or the 112 helpline
   - Sends an SMS with a live Google Maps link to the exact crash location
   - Publishes the crash event over **MQTT**
4. The companion **Flutter mobile app** subscribes to this MQTT topic and, via **Firebase Cloud Messaging**, immediately shows:
   - The crash location on an interactive map
   - Impact severity in G-values
   - One-tap **Navigate to Crash** and **Call Emergency** actions
   - Distance from the user's current location to the crash site

For demonstration, the full system is mounted on an RC car standing in for a real vehicle — bumping or crashing the car triggers the same emergency sequence a full-scale deployment would.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Motion sensing | MPU-9255 (accelerometer/gyroscope) |
| Edge compute | Raspberry Pi 5 |
| Cellular comms | SIM7600 G-H (calls, SMS, GPS) |
| Messaging | MQTT |
| Push notifications | Firebase Cloud Messaging |
| Mobile app | Flutter / Dart |
| Maps | flutter_map, Geolocator |
| Local storage | shared_preferences |

*(Pi-side scripting language: Python)*

---

## Repo Structure

```
ResQnet/
├── README.md
├── app/
│   ├── main.dart        # Flutter app - UI, MQTT client, Firebase messaging, map view
│   └── pubspec.yaml      # App dependencies
└── pi/
    └── ...               # Sensor reading, crash-detection logic, SIM7600 control, MQTT publish
```

---

## App Features

- **Live crash view** - auto-switches from an idle "all safe" screen to a full crash alert the moment an MQTT crash event arrives
- **Interactive map** with a marker at the crash site and a recenter button
- **Impact severity & G-force readout**
- **One-tap Navigate** (opens Google Maps) and **one-tap Call Emergency**
- **Configurable broker IP** - first-run setup dialog, persisted via `shared_preferences`
- **Configurable emergency contacts** - sent to the Pi over MQTT from within the app
- **Background push notifications** via Firebase, even when the app is closed

---

## Future Scope

- Direct **OBD-II** integration for real-vehicle deployment (beyond the RC car demo)
- Automatic **airbag-deployment detection**
- **AI-based severity prediction** from sensor data
- Cloud-linked emergency network to auto-notify **nearby hospitals and police stations**

---

## Status

Working prototype, demonstrated on a scaled RC car model. Patent filed; not yet deployed in a production vehicle.

---

## Author

Abhidnya Kulkarni — *(abhidnya.k24@gmail.com)*
