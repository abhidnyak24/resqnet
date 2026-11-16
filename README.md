# ResQNet
### Triple-Source Accident Detection and Autonomous Emergency Response

ResQNet is a vehicle-safety research project designed to detect accidents and initiate emergency notifications without requiring action from the occupants.

Its complete architecture combines vehicle-network airbag signals, inertial motion sensing, and external traffic verification. This repository contains the motion-based RC-car prototype and Flutter companion-app source.

**Indian patent application:** 202521090608.

## System Architecture

The complete design uses a Triple-Source Intelligent Verification (TSIV) framework:

### 1. Primary source: airbag deployment monitoring

An OBD-II/CAN interface monitors vehicle-specific messages indicating airbag deployment.

A deployment indication independently triggers the emergency protocol, without waiting for motion detection or traffic confirmation.

**Specified hardware:** ScanTool OBDLink SX connected to a Raspberry Pi 5.

### 2. Secondary source: inertial motion detection

An MPU-9255 measures acceleration and angular velocity to identify potential collision events.

The complete specification describes:
- Inertial sampling at least 1,000 Hz.
- Acceleration-change criteria in the 4–8 g range.
- Rotational changes exceeding 500°/s.
- Filtering and trained crash/non-crash classifiers.
- Configurable sensitivity that prioritizes minimizing missed accidents.

**Repository status:** Threshold-based motion detection is implemented. The current RC-car settings are 2.0 g and 200°/s.

### 3. Tertiary source: external traffic verification

After detection, the intended system queries external traffic services once per minute for up to ten minutes over a 1 km² geofenced area around the event.

The specification describes confirmation using:
- At least a 60% reduction in average lane speed for three consecutive samples; or
- Patterns suggestive of emergency-vehicle ingress.

This evidence updates event confidence and notification metadata.

“Satellite traffic verification” is the specification's terminology for this external traffic-data layer.

## Detection and Notification Sequence

**Airbag OR motion detection initiates the emergency protocol. Traffic verification follows in parallel and must not delay the initial notification.**

1. Detect an event from either vehicle-network signals or inertial motion.
2. Capture the event timestamp, location and available impact measurements.
3. Initiate emergency notifications.
4. Monitor external traffic conditions during the verification window.
5. Update confirmation and notification metadata as additional evidence arrives.

## Emergency Communication

The complete design specifies:
- Locally synthesized voice messages containing location, event time and assessed severity.
- Cellular voice calls with up to three attempts and callback detection.
- SMS and data notifications.
- Local caching and notification retries when connectivity returns.

The current prototype implements SMS attempts, MQTT publishing and sequential dialing of configured contacts.

## Current Prototype

The Raspberry Pi script:
- Reads MPU-9255 acceleration and gyro measurements.
- Applies impact, rotation and freefall-followed-by-impact rules.
- Queries GPS through the SIM7600 G-H.
- Publishes crash events over MQTT.
- Attempts SMS notifications and calls configured contacts.

The Flutter source provides:
- MQTT event reception.
- Crash reason, impact and severity display.
- Location map and navigation.
- Manual emergency-call action.
- Broker-address and emergency-contact configuration.
- Local notifications and Firebase integration scaffolding.

The original demonstration uses an RC car. Its thresholds and behavior should not be treated as validated full-size vehicle performance.

## Important Implementation Notes

- The current main loop sleeps for 5 ms in addition to sensor and processing time.
- GPS acquisition, SMS and dialing block that loop.
- Severity is a demonstration heuristic, not a validated injury assessment.
- The specification's configurable false-positive tolerance is a design policy, not a measured result.
- The repository does not establish zero missed accidents, classifier accuracy, guaranteed notification latency or six-hour backup operation.
- Vehicle-specific CAN messages must be validated before use.
- External traffic-provider capabilities and access must be verified before integration.

## Hardware and Software

| Component | Purpose |
|---|---|
| Raspberry Pi 5 | Onboard processing |
| MPU-9255 | Inertial sensing |
| SIM7600 G-H | Cellular communication and GPS |
| ScanTool OBDLink SX | Intended vehicle-network interface |
| Python | Prototype device software |
| MQTT | Event transport and configuration |
| Flutter / Dart | Companion application |

## Repository Layout

- `pi/resqnet_code.py` — sensor acquisition, detection and notifications.
- `app/main.dart` — Flutter companion-app source.

The repository does not currently include a complete Flutter project, dependency lockfile, Firebase configuration or notification backend.

## Development Priorities

1. Validate vehicle-specific CAN decoding and sensor acquisition.
2. Separate continuous sensing from GPS and notification operations.
3. Add durable event storage and delivery tracking.
4. Integrate external traffic verification without delaying initial alerts.
5. Implement and test speech synthesis, modem audio routing and call handling.
6. Package the app and backend.
7. Evaluate detection performance and validate backup power and secure updates.

## Author

Abhidnya Kulkarni  
abhidnya.k24@gmail.com
