"""Pan servo control — maps pan_deg (-180..180) to hobby servo PWM."""

from __future__ import annotations

import logging

import config

log = logging.getLogger(__name__)

_pigpio = None
_ready = False


def _pan_deg_to_servo_angle(pan_deg: int) -> int:
    pan_deg = max(config.PAN_MIN_DEG, min(config.PAN_MAX_DEG, pan_deg))
    return (pan_deg + config.PAN_MAX_DEG) // 2


def _angle_to_pulse_us(angle_deg: int) -> int:
    angle_deg = max(0, min(180, angle_deg))
    span = config.SERVO_MAX_PULSE_US - config.SERVO_MIN_PULSE_US
    return config.SERVO_MIN_PULSE_US + (angle_deg * span) // 180


def init() -> None:
    global _pigpio, _ready

    try:
        import pigpio

        pi = pigpio.pi()
        if not pi.connected:
            log.warning("pigpio daemon not running — start with: sudo pigpiod")
            return

        pi.set_mode(config.SERVO_GPIO, pigpio.OUTPUT)
        _pigpio = pi
        _ready = True
        set_pan_deg(0)
        log.info("Pan servo on GPIO%d (pigpio)", config.SERVO_GPIO)
    except ImportError:
        log.warning("pigpio not installed — servo disabled")
    except Exception as exc:
        log.warning("Servo init failed: %s", exc)


def set_pan_deg(pan_deg: int) -> None:
    if not _ready or _pigpio is None:
        return

    servo_angle = _pan_deg_to_servo_angle(pan_deg)
    pulse_us = _angle_to_pulse_us(servo_angle)
    _pigpio.set_servo_pulsewidth(config.SERVO_GPIO, pulse_us)
    log.debug("pan=%d -> servo %d deg (%d us)", pan_deg, servo_angle, pulse_us)


def cleanup() -> None:
    global _pigpio, _ready

    if _pigpio is not None:
        try:
            _pigpio.set_servo_pulsewidth(config.SERVO_GPIO, 0)
            _pigpio.stop()
        except Exception:
            pass
    _pigpio = None
    _ready = False
