"""Exercise actual dispatch function bodies without starting hardware or a loop."""

import ast
import contextlib
import io
import json
from pathlib import Path
import unittest
from unittest.mock import Mock

from pi.event_payload import build_crash_event, build_sms


class DispatchTests(unittest.TestCase):
    def setUp(self):
        source = Path(__file__).resolve().parents[1] / "pi" / "resqnet_code.py"
        tree = ast.parse(source.read_text())
        functions = ast.Module(
            body=[node for node in tree.body if isinstance(node, ast.FunctionDef)],
            type_ignores=[],
        )
        self.scope = {
            "json": json,
            "build_crash_event": build_crash_event,
            "build_sms": build_sms,
            "mqtt_client": Mock(),
            "EMERGENCY_NUMBERS": ["test-contact-1", "test-contact-2"],
            "USER_NAME": "Test",
        }
        exec(compile(functions, str(source), "exec"), self.scope)
        self.scope.update(
            get_gps_info=Mock(return_value=None),
            send_sms=Mock(return_value="OK"),
            call_all_numbers=Mock(),
        )

    def dispatch(self, impact=4):
        with contextlib.redirect_stdout(io.StringIO()):
            self.scope["notify_motion_event"]("gyro", impact, 1700000000)

    def test_gps_failure_still_notifies_with_original_timestamp(self):
        self.dispatch(impact=None)
        topic, payload = self.scope["mqtt_client"].publish.call_args.args
        event = json.loads(payload)
        self.assertEqual(topic, "resqnet/crash")
        self.assertEqual(event["timestamp"], 1700000000)
        self.assertIsNone(event["lat"])
        self.assertEqual(event["severity"], "unknown")
        self.assertEqual(self.scope["send_sms"].call_count, 2)
        self.scope["call_all_numbers"].assert_called_once_with()

    def test_sms_error_does_not_prevent_next_contact_or_calls(self):
        self.scope["send_sms"].side_effect = [OSError("modem failure"), "OK"]
        self.dispatch()
        self.assertEqual(self.scope["send_sms"].call_count, 2)
        self.assertEqual(self.scope["send_sms"].call_args.args[0], "test-contact-2")
        self.scope["call_all_numbers"].assert_called_once_with()

    def test_valid_gps_and_sequential_channels_remain_supported(self):
        self.scope["get_gps_info"].return_value = (18.5, 73.8)
        order = []
        self.scope["mqtt_client"].publish.side_effect = lambda *args, **kwargs: order.append("mqtt")
        self.scope["send_sms"].side_effect = lambda *args: order.append("sms")
        self.scope["call_all_numbers"].side_effect = lambda: order.append("calls")
        self.dispatch()
        self.assertEqual(order, ["mqtt", "sms", "sms", "calls"])
        self.assertIn("?q=18.500000,73.800000", self.scope["send_sms"].call_args.args[1])


if __name__ == "__main__":
    unittest.main()
