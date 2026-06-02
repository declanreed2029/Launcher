"""Lock / Launch state machine and timed launch sequence (server-authoritative)."""

from __future__ import annotations

import logging
import math
import threading
import time

import config
import servos

log = logging.getLogger(__name__)

_lock = threading.Lock()
_phase: str = "idle"  # idle | countdown | firing
_armed_until: float | None = None
_countdown_until: float | None = None
_cooldown_until: float | None = None
_sequence_thread: threading.Thread | None = None


def _seconds_left(deadline: float | None) -> int:
    if deadline is None:
        return 0
    return max(0, int(math.ceil(deadline - time.monotonic())))


def _is_armed(now: float) -> bool:
    return _armed_until is not None and now < _armed_until


def _derive_phase(now: float) -> str:
    if _phase == "countdown":
        return "countdown"
    if _phase == "firing":
        return "firing"
    if _cooldown_until is not None and now < _cooldown_until:
        return "cooldown"
    if _is_armed(now):
        return "armed"
    return "idle"


def _status_unlocked(now: float) -> dict:
    phase = _derive_phase(now)
    return {
        "launch_phase": phase,
        "armed": phase == "armed",
        "armed_seconds_left": _seconds_left(_armed_until) if _is_armed(now) else 0,
        "countdown_seconds_left": _seconds_left(_countdown_until)
        if phase == "countdown"
        else 0,
        "cooldown_seconds_left": _seconds_left(_cooldown_until)
        if phase == "cooldown"
        else 0,
        "launch_busy": _phase in ("countdown", "firing"),
    }


def status_dict() -> dict:
    with _lock:
        return _status_unlocked(time.monotonic())


def arm() -> dict:
    global _armed_until

    with _lock:
        now = time.monotonic()
        if _phase in ("countdown", "firing"):
            return {"ok": False, "error": "busy", **_status_unlocked(now)}

        _armed_until = now + config.LAUNCH_ARM_SEC
        log.info("Launch armed for %ds", config.LAUNCH_ARM_SEC)
        return {"ok": True, **_status_unlocked(now)}


def try_launch() -> dict:
    global _phase, _armed_until, _countdown_until, _sequence_thread

    with _lock:
        now = time.monotonic()
        if _phase in ("countdown", "firing"):
            return {"ok": False, "error": "busy", **_status_unlocked(now)}

        if not _is_armed(now):
            return {"ok": False, "error": "not_armed", **_status_unlocked(now)}

        _armed_until = None
        _phase = "countdown"
        _countdown_until = now + config.LAUNCH_COUNTDOWN_SEC
        log.info("Launch sequence started — %ds countdown", config.LAUNCH_COUNTDOWN_SEC)

        thread = threading.Thread(target=_run_sequence, daemon=True)
        _sequence_thread = thread
        thread.start()
        return {"ok": True, **_status_unlocked(now)}


def _wait_until(deadline: float) -> None:
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return
        time.sleep(min(remaining, 0.05))


def _run_sequence() -> None:
    global _phase, _countdown_until, _cooldown_until

    try:
        with _lock:
            countdown_end = _countdown_until

        if countdown_end is not None:
            _wait_until(countdown_end)

        with _lock:
            _phase = "firing"
            _countdown_until = None

        servos.set_launch_deg(config.LAUNCH_FIRE_DEG)
        time.sleep(config.LAUNCH_HOLD_SEC)
        servos.set_launch_deg(config.LAUNCH_REST_DEG)

        with _lock:
            _phase = "idle"
            _cooldown_until = time.monotonic() + config.LAUNCH_COOLDOWN_SEC
            log.info("Launch complete — %ds cooldown display", config.LAUNCH_COOLDOWN_SEC)
    except Exception:
        log.exception("Launch sequence failed")
        with _lock:
            _phase = "idle"
            _countdown_until = None
            servos.set_launch_deg(config.LAUNCH_REST_DEG)


def reset() -> None:
    """Test helper — clear all launch state."""
    global _phase, _armed_until, _countdown_until, _cooldown_until, _sequence_thread

    with _lock:
        _phase = "idle"
        _armed_until = None
        _countdown_until = None
        _cooldown_until = None
        _sequence_thread = None
