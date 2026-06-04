"""Unit tests for launch lock / countdown / sequence logic."""

from __future__ import annotations

import sys
import time
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

import config
import launch_controller


class TestLaunchController(unittest.TestCase):
    def setUp(self) -> None:
        launch_controller.reset()

    def tearDown(self) -> None:
        launch_controller.reset()

    def test_arm_then_status_armed(self) -> None:
        result = launch_controller.arm()
        self.assertTrue(result["ok"])
        self.assertEqual(result["launch_phase"], "armed")
        self.assertGreater(result["armed_seconds_left"], 0)

    def test_launch_without_arm_fails(self) -> None:
        result = launch_controller.try_launch()
        self.assertFalse(result["ok"])
        self.assertEqual(result["error"], "not_armed")

    def test_launch_starts_in_countdown_without_servo_yet(self) -> None:
        launch_controller.arm()
        with patch("launch_controller.servos.set_launch_deg") as mock_set:
            result = launch_controller.try_launch()
            self.assertTrue(result["ok"])
            self.assertEqual(result["launch_phase"], "countdown")
            self.assertGreater(result["countdown_seconds_left"], 0)
            mock_set.assert_not_called()
        launch_controller.reset()

    @patch("launch_controller._wait_until")
    @patch("launch_controller.servos.run_launch_sequence")
    def test_launch_sequence_fires_then_rests(self, mock_run, mock_wait) -> None:
        launch_controller.arm()
        launch_controller.try_launch()
        if launch_controller._sequence_thread:
            launch_controller._sequence_thread.join(timeout=5)

        mock_run.assert_called_once()

    @patch("launch_controller._wait_until")
    @patch("launch_controller.servos.run_launch_sequence")
    def test_launch_sets_cooldown_after_sequence(self, mock_run, mock_wait) -> None:
        launch_controller.arm()
        launch_controller.try_launch()
        if launch_controller._sequence_thread:
            launch_controller._sequence_thread.join(timeout=5)

        status = launch_controller.status_dict()
        self.assertGreaterEqual(status["cooldown_seconds_left"], 1)
        self.assertLessEqual(
            status["cooldown_seconds_left"], config.LAUNCH_COOLDOWN_SEC
        )

    @patch("launch_controller._wait_until")
    @patch("launch_controller.servos.run_launch_sequence")
    def test_double_launch_rejected_while_busy(self, mock_run, mock_wait) -> None:
        launch_controller.arm()
        first = launch_controller.try_launch()
        self.assertTrue(first["ok"])
        second = launch_controller.try_launch()
        self.assertFalse(second["ok"])
        self.assertEqual(second["error"], "busy")

        if launch_controller._sequence_thread:
            launch_controller._sequence_thread.join(timeout=5)

    def test_arm_expires(self) -> None:
        launch_controller.arm()
        launch_controller._armed_until = time.monotonic() - 0.1
        status = launch_controller.status_dict()
        self.assertEqual(status["launch_phase"], "idle")
        self.assertFalse(launch_controller.try_launch()["ok"])


class TestLaunchApi(unittest.TestCase):
    def setUp(self) -> None:
        import server

        self.client = server.app.test_client()
        launch_controller.reset()

    def tearDown(self) -> None:
        launch_controller.reset()

    def test_lock_endpoint(self) -> None:
        response = self.client.get("/api/lock")
        self.assertEqual(response.status_code, 200)
        data = response.get_json()
        self.assertTrue(data["ok"])
        self.assertEqual(data["launch_phase"], "armed")

    def test_launch_without_lock_403(self) -> None:
        response = self.client.get("/api/launch")
        self.assertEqual(response.status_code, 403)

    @patch("launch_controller._wait_until")
    @patch("launch_controller.servos.set_launch_deg")
    @patch("launch_controller.time.sleep", return_value=None)
    def test_status_includes_launch_fields(
        self, mock_sleep, mock_set_launch, mock_wait
    ) -> None:
        self.client.get("/api/lock")
        response = self.client.get("/api/status")
        data = response.get_json()
        self.assertEqual(data["launch_phase"], "armed")
        self.assertIn("countdown_seconds_left", data)
        self.assertIn("cooldown_seconds_left", data)


if __name__ == "__main__":
    unittest.main()
