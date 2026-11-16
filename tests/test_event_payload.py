import json
import unittest

from pi.event_payload import build_crash_event, build_sms


class EventPayloadTests(unittest.TestCase):
    def event(self, lat=18.5, lon=73.8, impact=4.0):
        return build_crash_event(lat, lon, "impact/gyro", impact, 1700000000)

    def test_valid_fix_and_detection_time_survive_serialization(self):
        event = json.loads(json.dumps(self.event(), allow_nan=False))
        self.assertEqual((event["lat"], event["lon"]), (18.5, 73.8))
        self.assertEqual(event["location_status"], "gps_fix")
        self.assertEqual(event["timestamp"], 1700000000)

    def test_gps_loss_has_no_fabricated_position_or_map_link(self):
        for lat, lon in [(None, None), (None, 73.8), (18.5, None)]:
            with self.subTest(lat=lat, lon=lon):
                event = self.event(lat, lon)
                self.assertIsNone(event["lat"])
                self.assertIsNone(event["lon"])
                self.assertEqual(event["location_status"], "unavailable")
                self.assertNotIn("https://", build_sms(event, "User"))
                self.assertIn("no GPS fix", build_sms(event, "User"))

    def test_invalid_fixes_are_unknown_and_strict_json_safe(self):
        for lat, lon in [(91, 0), (0, 181), (float("nan"), 0),
                         (0, float("inf")), (True, 1), ("18.5", 73.8)]:
            with self.subTest(lat=lat, lon=lon):
                event = self.event(lat, lon)
                self.assertIsNone(event["lat"])
                self.assertIsNone(event["lon"])
                json.dumps(event, allow_nan=False)

    def test_zero_coordinates_are_valid(self):
        event = self.event(0, 0)
        self.assertEqual(event["location_status"], "gps_fix")
        self.assertIn("?q=0.000000,0.000000", build_sms(event, "User"))

    def test_missing_or_invalid_acceleration_has_unknown_severity(self):
        for impact in [None, -1, float("nan"), float("inf"), True, "4"]:
            with self.subTest(impact=impact):
                event = self.event(impact=impact)
                self.assertEqual(event["severity"], "unknown")
                self.assertIsNone(event["impact_g"])
                json.dumps(event, allow_nan=False)
                self.assertIn("severity=unknown", build_sms(event, "User"))

    def test_severity_boundaries_keep_demo_heuristic(self):
        for impact, label in [(0, "low"), (1.49, "low"), (1.5, "medium"),
                              (2.99, "medium"), (3, "high"), (6, "high")]:
            with self.subTest(impact=impact):
                event = self.event(impact=impact)
                self.assertEqual(event["severity"], label)
                self.assertEqual(event["severity_basis"], "demo_acceleration_heuristic")

    def test_sms_carries_detection_time_and_severity(self):
        sms = build_sms(self.event(), "User")
        self.assertIn("2023-11-14T22:13:20Z", sms)
        self.assertIn("severity=high (demo)", sms)
        self.assertIn("?q=18.500000,73.800000", sms)

    def test_sms_template_fits_one_ascii_message(self):
        for lat, lon in [(None, None), (-90, -180), (90, 180)]:
            sms = build_sms(self.event(lat, lon, impact=None), "A" * 100 + "\x1a\n😀")
            self.assertTrue(sms.isascii())
            self.assertNotIn("\x1a", sms)
            self.assertLessEqual(len(sms), 160)

    def test_invalid_timestamp_rejected(self):
        for timestamp in [None, float("nan"), float("inf"), True]:
            with self.subTest(timestamp=timestamp), self.assertRaises(ValueError):
                build_crash_event(None, None, "motion", None, timestamp)


if __name__ == "__main__":
    unittest.main()
