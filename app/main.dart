
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';


Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("Background message received: ${message.notification?.title}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  runApp(const ResQNetApp());
}

class ResQNetApp extends StatelessWidget {
  const ResQNetApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme:
          ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)), 
      scaffoldBackgroundColor: const Color(0xFFF6F7FB),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(fontSize: 15),
      ),
    );
return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: const ResQNetHomePage(),
    );
}
}

class ResQNetHomePage extends StatefulWidget {
  const ResQNetHomePage({super.key});

  @override
  State<ResQNetHomePage> createState() => _ResQNetHomePageState();
}

class _ResQNetHomePageState extends State<ResQNetHomePage>
    with TickerProviderStateMixin {
  late FlutterLocalNotificationsPlugin notif;

  MqttServerClient? client;

  double? crashLat;
  double? crashLon;
String crashReason = "";
  bool crashDetected = false;

  String crashSeverity = "unknown";
  double? crashImpactG;
final MapController _mapController = MapController();
  bool _navBtnPressed = false;
  bool _callBtnPressed = false;
  String _connStatus = "Connecting…";
String? _brokerIp;
  final TextEditingController _ipController = TextEditingController();

  final TextEditingController _numberController = TextEditingController();

  double? _distanceKm;
LatLng? _myLatLng;

  @override
  void initState() {
    super.initState();
    _initNotifications();
    _requestNotifPermission();
    _loadIpAndConnect();
    _initLocation();
}

  Future<void> _loadIpAndConnect() async {
    final prefs = await SharedPreferences.getInstance();
    final String? savedIp = prefs.getString('broker_ip');
if (savedIp == null || savedIp.isEmpty) {
      setState(() {
        _connStatus = "No IP set";
      });
WidgetsBinding.instance.addPostFrameCallback((_) {
        _promptForIp(isInitialSetup: true);
});
} else {
      setState(() {
        _brokerIp = savedIp;
      });
await connectToPi();
    }
  }

  Future<void> _promptForIp({bool isInitialSetup = false}) async {
    _ipController.text = _brokerIp ??
'';

    await showDialog(
      context: context,
      barrierDismissible: !isInitialSetup,
      builder: (context) {
        return AlertDialog(
          title:
              Text(isInitialSetup ? 'Enter Broker IP' : 'Change Broker IP'),
          content: TextField(
           
 controller: _ipController,
            decoration: const InputDecoration(
              hintText: 'e.g., 192.168.1.15',
              label: Text('IP Address'),
            ),
            keyboardType: TextInputType.number,
          ),
          actions: [
      
      TextButton(
              onPressed: () async {
                final newIp = _ipController.text;
                if (newIp.isNotEmpty) {
                  final prefs = await SharedPreferences.getInstance();
                  
await prefs.setString('broker_ip', newIp);
                  setState(() {
                    _brokerIp = newIp;
                  });
                  Navigator.of(context).pop();
await connectToPi(); 
                }
              },
              child: const Text('Save and Connect'),
            ),
          ],
        );
},
    );
  }



  Future<void> _promptForNumber() async {
    _numberController.text = '';

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(

          title: const Text('Change Emergency Numbers'),

          content: TextField(
            controller: _numberController,
            decoration: const InputDecoration(

              hintText: 'e.g., +91111, +91222',
              label: Text('Numbers (comma-separated)'),

            ),
            keyboardType: TextInputType.phone,
          ),
          actions: [
            TextButton(
              onPressed: () {
                final newNumber = _numberController.text;

                if (newNumber.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Please enter at least one number.'),
                        backgroundColor: Colors.red),
                  );
                  return;
                }

                if (client == null ||
                    client?.connectionStatus?.state !=
                        MqttConnectionState.connected) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Not connected to Pi. Connect first.'),
                        backgroundColor: Colors.red),
                  );
                  return;
                }

                final builder = MqttClientPayloadBuilder();
                builder.addString(newNumber);

                client!.publishMessage(
                  'resqnet/config/number', 
                  MqttQos.atLeastOnce,
                  builder.payload!,
                );

                Navigator.of(context).pop();

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Emergency numbers sent to Pi!'),
                      backgroundColor: Colors.green),
                );
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }







  Future<void> _requestNotifPermission() async {
    final bool?
granted = await notif
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
print("Notification permission granted: $granted");
  }

  Future<void> _initNotifications() async {
    notif = FlutterLocalNotificationsPlugin();
const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
const InitializationSettings settings =
        InitializationSettings(android: androidInit);

    await notif.initialize(settings);
}

  Future<void> showCrashNotification(String severity, double? g) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'crash_channel',
      'Crash Alerts',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
    );
const NotificationDetails notifDetails =
        NotificationDetails(android: androidDetails);
await notif.show(
      0,
      'CRASH DETECTED — $severity',
      g == null ? 'Impact measurement unavailable' : 'Impact: ${g.toStringAsFixed(2)} g',
      notifDetails,
    );
}

  Future<void> _initLocation() async {
    try {
      final svcEnabled = await Geolocator.isLocationServiceEnabled();
if (!svcEnabled) return;
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
}
      if (perm == LocationPermission.deniedForever ||
          perm == LocationPermission.denied) {
        return;
}
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
setState(() {
        _myLatLng = LatLng(pos.latitude, pos.longitude);
      });
      _updateDistance();
} catch (_) {
}
  }

  Future<void> connectToPi() async {
    if (_brokerIp == null || _brokerIp!.isEmpty) {
      setState(() => _connStatus = "No IP set");
return;
    }

    try {
      setState(() => _connStatus = "Connecting…");
client = MqttServerClient.withPort(
        _brokerIp!,
        'resqnet_client',
        1883,
      );
client!.logging(on: false);
      client!.keepAlivePeriod = 20;
      client!.secure = false;
      client!.useWebSocket = false;
      client!.setProtocolV311();
final connMessage = MqttConnectMessage()
          .withClientIdentifier('resqnet_client')
          .withWillQos(MqttQos.atMostOnce)
          .startClean();
client!.connectionMessage = connMessage;

      client!.onConnected = () => setState(() => _connStatus = "Connected");
client!.onDisconnected = () =>
          setState(() => _connStatus = "Disconnected");
client!.onSubscribed =
          (t) => setState(() => _connStatus = "Subscribed: $t");
await client!.connect();

      client!.subscribe('resqnet/crash', MqttQos.atLeastOnce);

      client!.updates!.listen((List<MqttReceivedMessage<MqttMessage?>> events) {
        final MqttPublishMessage msg = events[0].payload as MqttPublishMessage;
        final payload =
            MqttPublishPayload.bytesToStringAsString(msg.payload.message);

        try {
          final data = jsonDecode(payload) as Map<String, dynamic>;
          if (data['type'] != 'crash') return;
          final lat = (data['lat'] as num?)?.toDouble();
          final lon = (data['lon'] as num?)?.toDouble();
          final hasLocation = lat != null && lon != null &&
              lat.isFinite && lon.isFinite &&
              lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180;
          final impact = (data['impact_g'] as num?)?.toDouble();
          if (!mounted) return;
          setState(() {
            crashLat = hasLocation ? lat : null;
            crashLon = hasLocation ? lon : null;
            crashReason = data['reason'] as String? ?? 'motion';
            crashImpactG = impact != null && impact.isFinite && impact >= 0
                ? impact : null;
            crashSeverity = data['severity'] as String? ?? 'unknown';
            crashDetected = true;
            _distanceKm = null;
          });
          showCrashNotification(crashSeverity, crashImpactG);
          _updateDistance();
          // The map must be mounted before its controller is moved.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && crashLat != null && crashLon != null) {
              _smoothZoomToCrash();
            }
          });
        } catch (error) {
          debugPrint('Ignoring malformed crash event: $error');
        }
      });
} catch (e) {
      setState(() => _connStatus = "Connect error");
}
  }

  void _updateDistance() {
    if (_myLatLng == null || crashLat == null || crashLon == null) return;
final d = Distance();
    final km = d.as(
      LengthUnit.Kilometer,
      _myLatLng!,
      LatLng(crashLat!, crashLon!),
    );
setState(() {
      _distanceKm = km;
    });
}

  Future<void> _smoothZoomToCrash() async {
    if (crashLat == null || crashLon == null) return;
final target = LatLng(crashLat!, crashLon!);
    final steps = <double>[12, 13.5, 15, 16];
for (final z in steps) {
      _mapController.move(target, z);
      await Future.delayed(const Duration(milliseconds: 90));
}
  }

  void _recenterOnCrash() {
    if (crashLat == null || crashLon == null) return;
    _smoothZoomToCrash();
}

  void _navigateToCrash() async {
    if (crashLat == null || crashLon == null) return;
final uri = Uri.parse(
      "https://www.google.com/maps/dir/?api=1&destination=$crashLat,$crashLon",
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
}

  void _callEmergency() {
    launchUrl(Uri.parse("tel:112"));
}

Widget _statusChip() {
    Color c;
    String displayText;
if (_connStatus.startsWith("Connected") ||
        _connStatus.startsWith("Subscribed")) {
      c = const Color(0xFF12B981);
displayText = "Connected";
} else if (_connStatus.startsWith("Connecting")) {
      c = const Color(0xFFF59E0B);
displayText = "Connecting...";
} else {
      c = const Color(0xFFEF4444);
displayText = "Disconnected";
}

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withOpacity(0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
        
    width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
     
     Text(
            displayText, 
            style: TextStyle(
              color: c,
             
 fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
}
Widget _card({required Widget child}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x11000000)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
     
       blurRadius: 12,
            offset: Offset(0, 6),
          )
        ],
      ),
      child: child,
    );
}



Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Row(
        children: [
    
      Row(
            mainAxisSize: MainAxisSize.min, 
            children: [
              const Text(
                "ResQNet",
                style: TextStyle(
               
   fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                ),
              ),
     
         IconButton(
                icon: const Icon(Icons.settings_ethernet),
                tooltip: 'Change Broker IP',
                onPressed: () => _promptForIp(),
              ),

              IconButton(
                icon: const Icon(Icons.contact_phone_outlined),
                tooltip: 'Change Emergency Number',
                onPressed: _promptForNumber, 
              ),
            ],
         
 ),

          const Spacer(),

_statusChip(),
        ],
      ),
    );
}
@override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: crashDetected ? _crashView() : _idleView(),
      ),
    );
}

  Widget _idleView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(),
        const SizedBox(height: 8),
        _card(
          child: Row(
            children: [
              const 
Icon(Icons.shield_outlined,
                  size: 28, color: Color(0xFF12B981)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Everything is looking safe right now :)",
        
          style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
   
     const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            "Monitoring for crash events on your network.",
            style: TextStyle(color: Colors.black.withOpacity(0.6)),
          ),
        ),
      ],
    );
}





  Widget _crashView() {

    final crash = crashLat != null && crashLon != null
        ? LatLng(crashLat!, crashLon!) : null;
    final distanceText =
        _distanceKm != null ? "${_distanceKm!.toStringAsFixed(1)} km away" : "—";

    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "CRASH DETECTED",
                style: TextStyle(
                  color: Color(0xFFEF4444),
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "Reason: $crashReason",
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                "Severity estimate: ${crashSeverity.toUpperCase()}",
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.red,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                crashImpactG == null
                    ? "Impact: unavailable"
                    : "Impact: ${crashImpactG!.toStringAsFixed(2)} g",
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.social_distance_outlined, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    "Distance: $distanceText",
                    style: TextStyle(color: Colors.black.withOpacity(0.7)),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _card(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: crash == null
                  ? const Center(
                      child: Text('GPS unavailable. Crash alert received without a location.'),
                    )
                  : Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: crash,
                      initialZoom: 15,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.resqnet',
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: crash,
                            width: 44,
                            height: 44,
                            child: const Icon(
                              Icons.location_on,
                              color: Color(0xFFEF4444),
                              size: 44,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Material(
                      color: Colors.white,
                      shape: const CircleBorder(),
                      elevation: 2,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _recenterOnCrash,
                        child: const Padding(
                          padding: EdgeInsets.all(10),
                          child: Icon(Icons.my_location, size: 20),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTapDown: (_) => setState(() => _navBtnPressed = true),
                  onTapCancel: () => setState(() => _navBtnPressed = false),
                  onTapUp: (_) => setState(() => _navBtnPressed = false),
                  onTap: crash == null ? null : _navigateToCrash,
                  child: AnimatedScale(
                    scale: _navBtnPressed ? 0.97 : 1.0,
                    duration: const Duration(milliseconds: 90),
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2563EB),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x14000000),
                            blurRadius: 10,
                            offset: Offset(0, 6),
                          )
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.navigation, color: Colors.white),
                          SizedBox(width: 8),
                          Text(
                            crash == null ? "Location unavailable" : "Navigate to Crash",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTapDown: (_) => setState(() => _callBtnPressed = true),
                  onTapCancel: () => setState(() => _callBtnPressed = false),
                  onTapUp: (_) => setState(() => _callBtnPressed = false),
                  onTap: _callEmergency,
                  child: AnimatedScale(
                    scale: _callBtnPressed ? 0.97 : 1.0,
                    duration: const Duration(milliseconds: 90),
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x14000000),
                            blurRadius: 10,
                            offset: Offset(0, 6),
                          )
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.call, color: Colors.white),
                          SizedBox(width: 8),
                          Text(
                            "Call Emergency",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
