"""Hardware-independent event metadata for the existing motion prototype.

Absent GPS and acceleration measurements remain unknown.
Severity is an acceleration heuristic, not a validated injury assessment.
"""

import math
from datetime import datetime, timezone


def _finite_number(value):
    return (
        isinstance(value, (int, float))
        and not isinstance(value, bool)
        and math.isfinite(value)
    )


def build_crash_event(lat, lon, reason, impact_g, detected_at):
    if not _finite_number(detected_at):
        raise ValueError("A finite detection timestamp is required")
    location_valid = (
        _finite_number(lat) and _finite_number(lon)
        and -90 <= lat <= 90 and -180 <= lon <= 180
    )
    if not _finite_number(impact_g) or impact_g < 0:
        impact_g = None
    severity = "unknown"
    if impact_g is not None:
        severity = "low" if impact_g < 1.5 else "medium" if impact_g < 3 else "high"
    return {
        "schema_version": 1,
        "type": "crash",
        "lat": lat if location_valid else None,
        "lon": lon if location_valid else None,
        "location_status": "gps_fix" if location_valid else "unavailable",
        "reason": reason,
        "detection_method": "motion",
        "impact_g": impact_g,
        "severity": severity,
        "severity_basis": "demo_acceleration_heuristic",
        "timestamp": detected_at,
    }


def build_sms(event, user_name):
    timestamp = datetime.fromtimestamp(event["timestamp"], timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    if event["lat"] is None or event["lon"] is None:
        location = "Location: unavailable (no GPS fix)"
    else:
        location = f'https://maps.google.com/?q={event["lat"]:.6f},{event["lon"]:.6f}'
    # Keep the ASCII template within one SMS for a bounded display name.
    name = "".join(c for c in user_name if c.isascii() and c.isalnum())[:24] or "User"
    return (
        f"ResQNet motion: {name}\n"
        f"{timestamp}; severity={event['severity']} (demo)\n"
        f"{location}"
    )
