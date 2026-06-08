"""Launch servo must use angle pulses at 0°, not PWM-off."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

import config
import servos


class TestLaunchServoPulse(unittest.TestCase):
    def test_zero_deg_is_minimum_pulse_not_off(self) -> None:
        self.assertEqual(servos.angle_to_pulse_us(0), config.SERVO_MIN_PULSE_US)
        self.assertGreater(servos.angle_to_pulse_us(0), 0)

    def test_launch_invert_symmetric_strokes(self) -> None:
        with patch.object(config, "LAUNCH_REST_DEG", 0), patch.object(
            config, "LAUNCH_FIRE_DEG", 92
        ), patch.object(config, "LAUNCH_INVERT", True):
            self.assertEqual(servos.launch_deg_to_servo_angle(0), 92)
            self.assertEqual(servos.launch_deg_to_servo_angle(92), 0)
        with patch.object(config, "LAUNCH_REST_DEG", 0), patch.object(
            config, "LAUNCH_FIRE_DEG", 92
        ), patch.object(config, "LAUNCH_INVERT", False):
            self.assertEqual(servos.launch_deg_to_servo_angle(0), 0)
            self.assertEqual(servos.launch_deg_to_servo_angle(92), 92)


if __name__ == "__main__":
    unittest.main()
