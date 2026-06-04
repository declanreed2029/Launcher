"""Pan + tilt + launch hobby servos via pigpio.

PWM is only sent briefly on each move, then released (pulse 0) so servos stay
quiet at rest. Launch hold uses sustained PWM for LAUNCH_HOLD_SEC.
"""

from __future__ import annotations

import logging
import threading

import config

log = logging.getLogger(__name__)

_pi = None
_ready = False
_release_timers: dict[int, threading.Timer] = {}
_timer_lock = threading.Lock()


def pan_deg_to_servo_angle(pan_deg: int) -> int:
    """Map HUD pan (-180..180) to servo travel (0..180), same as ESP32 pan_servo.c."""
    pan_deg = max(config.PAN_MIN_DEG, min(config.PAN_MAX_DEG, pan_deg))
    return (pan_deg + config.PAN_MAX_DEG) // 2


def tilt_deg_to_servo_angle(tilt_deg: int) -> int:
    """Map HUD tilt (0..180) directly to servo angle."""
    return max(config.TILT_MIN_DEG, min(config.TILT_MAX_DEG, tilt_deg))


def angle_to_pulse_us(angle_deg: int) -> int:
    angle_deg = max(0, min(180, angle_deg))
    span = config.SERVO_MAX_PULSE_US - config.SERVO_MIN_PULSE_US
    return config.SERVO_MIN_PULSE_US + (angle_deg * span) // 180


def _cancel_release(gpio: int) -> None:
    with _timer_lock:
        timer = _release_timers.pop(gpio, None)
    if timer is not None:
        timer.cancel()


def _schedule_release(gpio: int) -> None:
    delay_s = config.SERVO_RELEASE_MS / 1000.0

    def _release() -> None:
        if _pi is not None:
            _pi.set_servo_pulsewidth(gpio, 0)
        with _timer_lock:
            _release_timers.pop(gpio, None)

    with _timer_lock:
        old = _release_timers.pop(gpio, None)
        if old is not None:
            old.cancel()
        _release_timers[gpio] = threading.Timer(delay_s, _release)
        _release_timers[gpio].daemon = True
        _release_timers[gpio].start()


def _drive(gpio: int, pulse_us: int, *, hold: bool) -> None:
    if not _ready or _pi is None:
        return

    _cancel_release(gpio)
    if pulse_us <= 0:
        _pi.set_servo_pulsewidth(gpio, 0)
        return

    _pi.set_servo_pulsewidth(gpio, pulse_us)
    if not hold:
        _schedule_release(gpio)


def release_all() -> None:
    """Stop PWM on all servo pins (quiet idle, no buzz)."""
    for gpio in (
        config.PAN_SERVO_GPIO,
        config.TILT_SERVO_GPIO,
        config.LAUNCH_SERVO_GPIO,
    ):
        _cancel_release(gpio)
        if _pi is not None:
            _pi.set_servo_pulsewidth(gpio, 0)


def init() -> None:
    global _pi, _ready

    try:
        import pigpio

        pi = pigpio.pi()
        if not pi.connected:
            log.warning("pigpio daemon not running — start with: sudo pigpiod")
            return

        pi.set_mode(config.PAN_SERVO_GPIO, pigpio.OUTPUT)
        pi.set_mode(config.TILT_SERVO_GPIO, pigpio.OUTPUT)
        pi.set_mode(config.LAUNCH_SERVO_GPIO, pigpio.OUTPUT)
        _pi = pi
        _ready = True
        release_all()
        log.info(
            "Servos ready — pan GPIO%d, tilt GPIO%d, launch GPIO%d (PWM idle until move)",
            config.PAN_SERVO_GPIO,
            config.TILT_SERVO_GPIO,
            config.LAUNCH_SERVO_GPIO,
        )
    except ImportError:
        log.warning("pigpio not installed — servos disabled")
    except Exception as exc:
        log.warning("Servo init failed: %s", exc)


def set_pan_deg(pan_deg: int) -> None:
    if not _ready or _pi is None:
        return

    servo_angle = pan_deg_to_servo_angle(pan_deg)
    pulse_us = angle_to_pulse_us(servo_angle)
    _drive(config.PAN_SERVO_GPIO, pulse_us, hold=False)
    log.debug("pan=%d -> %d deg (%d us)", pan_deg, servo_angle, pulse_us)


def set_tilt_deg(tilt_deg: int) -> None:
    if not _ready or _pi is None:
        return

    servo_angle = tilt_deg_to_servo_angle(tilt_deg)
    pulse_us = angle_to_pulse_us(servo_angle)
    _drive(config.TILT_SERVO_GPIO, pulse_us, hold=False)
    log.debug("tilt=%d -> %d deg (%d us)", tilt_deg, servo_angle, pulse_us)


def set_launch_deg(angle_deg: int, *, hold: bool = False) -> None:
    if not _ready or _pi is None:
        return

    angle_deg = max(0, min(180, angle_deg))
    pulse_us = angle_to_pulse_us(angle_deg) if angle_deg > 0 else 0
    _drive(config.LAUNCH_SERVO_GPIO, pulse_us, hold=hold)
    log.info("launch servo -> %d deg (%d us, hold=%s)", angle_deg, pulse_us, hold)


def cleanup() -> None:
    global _pi, _ready

    release_all()
    if _pi is not None:
        try:
            _pi.stop()
        except Exception:
            pass
    _pi = None
    _ready = False
