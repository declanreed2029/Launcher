"""Unit tests for pan/tilt servo mapping and server move logic."""

from __future__ import annotations

import importlib
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

import config
import servos


class TestServoMapping(unittest.TestCase):
    def test_pan_center(self) -> None:
        self.assertEqual(servos.pan_deg_to_servo_angle(0), 90)

    def test_pan_min(self) -> None:
        self.assertEqual(servos.pan_deg_to_servo_angle(-180), 0)

    def test_pan_max(self) -> None:
        self.assertEqual(servos.pan_deg_to_servo_angle(180), 180)

    def test_pan_clamps(self) -> None:
        self.assertEqual(servos.pan_deg_to_servo_angle(-999), 0)
        self.assertEqual(servos.pan_deg_to_servo_angle(999), 180)

    def test_tilt_mid(self) -> None:
        self.assertEqual(servos.tilt_deg_to_servo_angle(90), 90)

    def test_tilt_min(self) -> None:
        self.assertEqual(servos.tilt_deg_to_servo_angle(0), 0)

    def test_tilt_max(self) -> None:
        self.assertEqual(servos.tilt_deg_to_servo_angle(180), 180)

    def test_tilt_clamps(self) -> None:
        self.assertEqual(servos.tilt_deg_to_servo_angle(-50), 0)
        self.assertEqual(servos.tilt_deg_to_servo_angle(250), 180)

    def test_pulse_us_endpoints(self) -> None:
        self.assertEqual(servos.angle_to_pulse_us(0), config.SERVO_MIN_PULSE_US)
        self.assertEqual(servos.angle_to_pulse_us(180), config.SERVO_MAX_PULSE_US)
        self.assertEqual(servos.angle_to_pulse_us(90), 1500)


class TestServerMoves(unittest.TestCase):
    def setUp(self) -> None:
        import server

        self.server = server
        server._pan_deg = 0
        server._tilt_deg = 90

    @patch.object(servos, "set_pan_deg")
    @patch.object(servos, "set_tilt_deg")
    def test_left_updates_pan_only(self, mock_tilt, mock_pan) -> None:
        self.server._apply_move("left")
        self.assertEqual(self.server._pan_deg, -5)
        self.assertEqual(self.server._tilt_deg, 90)
        mock_pan.assert_called_once_with(-5)
        mock_tilt.assert_called_once_with(90)

    @patch.object(servos, "set_pan_deg")
    @patch.object(servos, "set_tilt_deg")
    def test_right_updates_pan_only(self, mock_tilt, mock_pan) -> None:
        self.server._apply_move("right")
        self.assertEqual(self.server._pan_deg, 5)
        mock_pan.assert_called_once_with(5)
        mock_tilt.assert_called_once_with(90)

    @patch.object(servos, "set_pan_deg")
    @patch.object(servos, "set_tilt_deg")
    def test_up_updates_tilt_only(self, mock_tilt, mock_pan) -> None:
        self.server._apply_move("up")
        self.assertEqual(self.server._tilt_deg, 85)
        self.assertEqual(self.server._pan_deg, 0)
        mock_tilt.assert_called_once_with(85)
        mock_pan.assert_called_once_with(0)

    @patch.object(servos, "set_pan_deg")
    @patch.object(servos, "set_tilt_deg")
    def test_down_updates_tilt_only(self, mock_tilt, mock_pan) -> None:
        self.server._apply_move("down")
        self.assertEqual(self.server._tilt_deg, 95)
        mock_tilt.assert_called_once_with(95)
        mock_pan.assert_called_once_with(0)

    @patch.object(servos, "set_pan_deg")
    @patch.object(servos, "set_tilt_deg")
    def test_center_resets_both(self, mock_tilt, mock_pan) -> None:
        self.server._pan_deg = 40
        self.server._tilt_deg = 120
        self.server._apply_move("center")
        self.assertEqual(self.server._pan_deg, 0)
        self.assertEqual(self.server._tilt_deg, 90)
        mock_pan.assert_called_once_with(0)
        mock_tilt.assert_called_once_with(90)

    @patch.object(servos, "set_pan_deg")
    @patch.object(servos, "set_tilt_deg")
    def test_tilt_clamps_at_min(self, mock_tilt, mock_pan) -> None:
        self.server._tilt_deg = 2
        self.server._apply_move("up")
        self.assertEqual(self.server._tilt_deg, 0)
        mock_tilt.assert_called_once_with(0)

    @patch.object(servos, "set_pan_deg")
    @patch.object(servos, "set_tilt_deg")
    def test_tilt_clamps_at_max(self, mock_tilt, mock_pan) -> None:
        self.server._tilt_deg = 178
        self.server._apply_move("down")
        self.assertEqual(self.server._tilt_deg, 180)
        mock_tilt.assert_called_once_with(180)

    @patch.object(servos, "set_pan_deg")
    @patch.object(servos, "set_tilt_deg")
    def test_sequence_matches_hud_steps(self, mock_tilt, mock_pan) -> None:
        for _ in range(3):
            self.server._apply_move("up")
        self.assertEqual(self.server._tilt_deg, 75)
        for _ in range(3):
            self.server._apply_move("down")
        self.assertEqual(self.server._tilt_deg, 90)
        mock_tilt.assert_called_with(90)


class TestFlaskCmdEndpoint(unittest.TestCase):
    def setUp(self) -> None:
        import server

        self.app = server.app
        self.client = self.app.test_client()
        server._pan_deg = 0
        server._tilt_deg = 90

    @patch.object(servos, "set_pan_deg")
    @patch.object(servos, "set_tilt_deg")
    def test_cmd_up_ok(self, mock_tilt, mock_pan) -> None:
        response = self.client.get("/cmd?move=up")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data, b"OK")
        mock_tilt.assert_called_once_with(85)

    @patch.object(servos, "set_pan_deg")
    @patch.object(servos, "set_tilt_deg")
    def test_cmd_down_ok(self, mock_tilt, mock_pan) -> None:
        response = self.client.get("/cmd?move=down")
        self.assertEqual(response.status_code, 200)
        mock_tilt.assert_called_once_with(95)

    @patch.object(servos, "set_pan_deg")
    @patch.object(servos, "set_tilt_deg")
    def test_status_json_after_moves(self, mock_tilt, mock_pan) -> None:
        self.client.get("/cmd?move=right")
        self.client.get("/cmd?move=down")
        response = self.client.get("/api/status")
        data = response.get_json()
        self.assertEqual(data["pan_deg"], 5)
        self.assertEqual(data["tilt_deg"], 95)


if __name__ == "__main__":
    unittest.main()
