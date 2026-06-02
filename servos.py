"""Pan + tilt hobby servos via pigpio (shared daemon connection)."""

from __future__ import annotations

import logging

import config

log = logging.getLogger(__name__)

_pi = None
_ready = False


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
        set_pan_deg(0)
        set_tilt_deg(90)
        set_launch_deg(config.LAUNCH_REST_DEG)
        log.info(
            "Servos ready — pan GPIO%d, tilt GPIO%d, launch GPIO%d",
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
    _pi.set_servo_pulsewidth(config.PAN_SERVO_GPIO, pulse_us)
    log.debug("pan=%d -> %d deg (%d us)", pan_deg, servo_angle, pulse_us)


def set_tilt_deg(tilt_deg: int) -> None:
    if not _ready or _pi is None:
        return

    servo_angle = tilt_deg_to_servo_angle(tilt_deg)
    pulse_us = angle_to_pulse_us(servo_angle)
    _pi.set_servo_pulsewidth(config.TILT_SERVO_GPIO, pulse_us)
    log.debug("tilt=%d -> %d deg (%d us)", tilt_deg, servo_angle, pulse_us)


def set_launch_deg(angle_deg: int) -> None:
    if not _ready or _pi is None:
        return

    angle_deg = max(0, min(180, angle_deg))
    pulse_us = angle_to_pulse_us(angle_deg)
    _pi.set_servo_pulsewidth(config.LAUNCH_SERVO_GPIO, pulse_us)
    log.info("launch servo -> %d deg (%d us)", angle_deg, pulse_us)


def cleanup() -> None:
    global _pi, _ready

    if _pi is not None:
        try:
            _pi.set_servo_pulsewidth(config.PAN_SERVO_GPIO, 0)
            _pi.set_servo_pulsewidth(config.TILT_SERVO_GPIO, 0)
            _pi.set_servo_pulsewidth(config.LAUNCH_SERVO_GPIO, 0)
            _pi.stop()
        except Exception:
            pass
    _pi = None
    _ready = False
