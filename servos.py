"""Pan + tilt + launch hobby servos via pigpio.

PWM is only sent briefly on each move, then released (pulse 0) so servos stay
quiet at rest. Launch hold uses sustained PWM for LAUNCH_HOLD_SEC.
"""

from __future__ import annotations

import logging
import os
import subprocess
import threading
import time

import config

log = logging.getLogger(__name__)

_pi = None
_ready = False
_release_timers: dict[int, threading.Timer] = {}
_timer_lock = threading.Lock()
_pi_lock = threading.Lock()
_last_pigpiod_restart = 0.0
_pigpiod_restart_count = 0
_last_drive_error: str | None = None


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


def _release_ms_for_gpio(gpio: int) -> int:
    if gpio == config.TILT_SERVO_GPIO:
        return config.SERVO_TILT_RELEASE_MS
    if gpio == config.LAUNCH_SERVO_GPIO:
        return config.LAUNCH_RETURN_MS
    return config.SERVO_RELEASE_MS


def _schedule_release(gpio: int) -> None:
    delay_s = _release_ms_for_gpio(gpio) / 1000.0

    def _release() -> None:
        with _pi_lock:
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


def _drive(gpio: int, pulse_us: int, *, hold: bool) -> bool:
    if not ensure_ready() or _pi is None:
        _set_drive_error("pigpio not ready")
        log.warning("GPIO%d drive skipped — pigpio not ready", gpio)
        return False

    with _pi_lock:
        if not _ensure_gpio_output(gpio):
            return False

        with _timer_lock:
            timer = _release_timers.pop(gpio, None)
        if timer is not None:
            timer.cancel()

        if pulse_us <= 0:
            _pigpio_ok(_pi.set_servo_pulsewidth(gpio, 0), gpio, "PWM off")
            return True

        if not _pigpio_ok(
            _pi.set_servo_pulsewidth(gpio, pulse_us), gpio, f"pulse {pulse_us}us"
        ):
            return False

        _set_drive_error(None)

    if not hold:
        _schedule_release(gpio)
    return True


def release_all() -> None:
    """Stop PWM on all servo pins (quiet idle, no buzz)."""
    with _pi_lock:
        for gpio in (
            config.PAN_SERVO_GPIO,
            config.TILT_SERVO_GPIO,
            config.LAUNCH_SERVO_GPIO,
        ):
            with _timer_lock:
                timer = _release_timers.pop(gpio, None)
            if timer is not None:
                timer.cancel()
            if _pi is not None:
                _ensure_gpio_output(gpio)
                _pi.set_servo_pulsewidth(gpio, 0)


def is_ready() -> bool:
    return _ready and _pi is not None and _pi.connected


def pigpiod_restart_count() -> int:
    return _pigpiod_restart_count


def last_drive_error() -> str | None:
    return _last_drive_error


def _set_drive_error(msg: str | None) -> None:
    global _last_drive_error
    _last_drive_error = msg


def _ensure_gpio_output(gpio: int) -> bool:
    """Pins can be left INPUT after stop_servos.sh — reassert OUTPUT before PWM."""
    if _pi is None:
        return False
    try:
        import pigpio

        if _pi.get_mode(gpio) != pigpio.OUTPUT:
            log.warning("GPIO%d was not OUTPUT — reconfiguring (common after stop_servos)", gpio)
            _pi.set_mode(gpio, pigpio.OUTPUT)
        return True
    except Exception as exc:
        _set_drive_error(f"GPIO{gpio} mode: {exc}")
        log.warning("GPIO%d set_mode failed: %s", gpio, exc)
        return False


def _pigpio_ok(result: int, gpio: int, action: str) -> bool:
    if result >= 0:
        return True
    _set_drive_error(f"GPIO{gpio} {action} failed (code {result})")
    log.error("GPIO%d %s failed (pigpio code %d)", gpio, action, result)
    return False


def _try_restart_pigpiod() -> None:
    """Restart pigpiod after brownout or daemon crash (launcher runs as root)."""
    global _pigpiod_restart_count

    pigpiod_path = None
    for candidate in ("/usr/bin/pigpiod", "/usr/local/bin/pigpiod"):
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            pigpiod_path = candidate
            break

    try:
        subprocess.run(
            ["systemctl", "restart", "pigpiod"],
            timeout=15,
            check=False,
            capture_output=True,
        )
        time.sleep(0.75)
        _pigpiod_restart_count += 1
        log.warning("Restarted pigpiod via systemctl (count=%d)", _pigpiod_restart_count)
        return
    except Exception as exc:
        log.debug("systemctl restart pigpiod failed: %s", exc)

    if pigpiod_path:
        try:
            subprocess.run(["pkill", "-x", "pigpiod"], timeout=5, check=False)
            time.sleep(0.25)
            subprocess.Popen([pigpiod_path])
            time.sleep(0.75)
            _pigpiod_restart_count += 1
            log.warning("Restarted pigpiod directly (count=%d)", _pigpiod_restart_count)
        except Exception as exc:
            log.warning("Direct pigpiod restart failed: %s", exc)


def init() -> bool:
    global _pi, _ready

    try:
        import pigpio

        pi = pigpio.pi()
        if not pi.connected:
            log.warning("pigpio daemon not running — start with: sudo pigpiod")
            _ready = False
            return False

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
        return True
    except ImportError:
        log.warning("pigpio not installed — servos disabled")
    except Exception as exc:
        log.warning("Servo init failed: %s", exc)

    _ready = False
    return False


def ensure_ready() -> bool:
    """Connect to pigpiod; restart daemon if brownout killed it."""
    global _pi, _ready, _last_pigpiod_restart

    if _pi is not None and _pi.connected:
        return True

    _ready = False
    if _pi is not None:
        try:
            _pi.stop()
        except Exception:
            pass
        _pi = None

    if init():
        return True

    if not config.PIGPIO_AUTO_RESTART:
        return False

    now = time.monotonic()
    if now - _last_pigpiod_restart < config.PIGPIO_RESTART_COOLDOWN_SEC:
        return False

    _last_pigpiod_restart = now
    log.warning(
        "pigpio not connected — retrying after pigpiod restart "
        "(often caused by undervoltage / 1A supply)"
    )
    _try_restart_pigpiod()
    return init()


def set_pan_deg(pan_deg: int) -> None:
    if not ensure_ready() or _pi is None:
        return

    servo_angle = pan_deg_to_servo_angle(pan_deg)
    pulse_us = angle_to_pulse_us(servo_angle)
    _drive(config.PAN_SERVO_GPIO, pulse_us, hold=False)
    log.debug("pan=%d -> %d deg (%d us)", pan_deg, servo_angle, pulse_us)


def set_tilt_deg(tilt_deg: int) -> None:
    if not ensure_ready() or _pi is None:
        return

    servo_angle = tilt_deg_to_servo_angle(tilt_deg)
    pulse_us = angle_to_pulse_us(servo_angle)
    _drive(config.TILT_SERVO_GPIO, pulse_us, hold=False)
    log.info("tilt=%d -> %d deg (%d us)", tilt_deg, servo_angle, pulse_us)


def _ensure_launch_output() -> None:
    _ensure_gpio_output(config.LAUNCH_SERVO_GPIO)


def release_launch() -> None:
    """Stop PWM on launch pin (keep OUTPUT so the next fire can drive immediately)."""
    with _timer_lock:
        timer = _release_timers.pop(config.LAUNCH_SERVO_GPIO, None)
    if timer is not None:
        timer.cancel()
    with _pi_lock:
        if _pi is not None:
            _ensure_gpio_output(config.LAUNCH_SERVO_GPIO)
            _pi.set_servo_pulsewidth(config.LAUNCH_SERVO_GPIO, 0)


def launch_deg_to_servo_angle(angle_deg: int) -> int:
    """Map HUD launch angle to servo travel.

    Rest always returns to the same CW base. Invert flips fire to the opposite
    ±LAUNCH_FIRE_DEG stroke (e.g. rest 92° / fire 0° vs rest 0° / fire 92°),
    never rest at 180° which caused ~184° rotation one way.
    """
    angle_deg = max(0, min(180, angle_deg))
    hud_rest = max(0, min(180, config.LAUNCH_REST_DEG))
    travel = max(0, min(180, config.LAUNCH_FIRE_DEG))

    if angle_deg <= hud_rest:
        if config.LAUNCH_INVERT:
            return travel
        return hud_rest

    move = min(angle_deg - hud_rest, travel)
    if config.LAUNCH_INVERT:
        return max(0, min(180, travel - move))
    return max(0, min(180, hud_rest + move))


def set_launch_deg(angle_deg: int, *, hold: bool = False) -> None:
    if not ensure_ready() or _pi is None:
        return

    _ensure_launch_output()
    angle_deg = max(0, min(180, angle_deg))
    servo_angle = launch_deg_to_servo_angle(angle_deg)
    pulse_us = angle_to_pulse_us(servo_angle)
    _drive(config.LAUNCH_SERVO_GPIO, pulse_us, hold=hold)
    log.info(
        "launch servo -> %d deg (servo %d deg, %d us, hold=%s, invert=%s)",
        angle_deg,
        servo_angle,
        pulse_us,
        hold,
        config.LAUNCH_INVERT,
    )


def run_launch_sequence() -> None:
    """Fire (held), return to rest with one timed pulse, then stop PWM."""
    if not ensure_ready():
        log.error("Launch sequence aborted — pigpio not ready")
        return

    _ensure_launch_output()
    if not _drive(config.LAUNCH_SERVO_GPIO, angle_to_pulse_us(
        launch_deg_to_servo_angle(config.LAUNCH_FIRE_DEG)
    ), hold=True):
        log.error("Launch fire pulse failed")
        return

    time.sleep(config.LAUNCH_HOLD_SEC)

    if not _drive(config.LAUNCH_SERVO_GPIO, angle_to_pulse_us(
        launch_deg_to_servo_angle(config.LAUNCH_REST_DEG)
    ), hold=False):
        log.error("Launch return pulse failed")
        return

    time.sleep(config.LAUNCH_RETURN_MS / 1000.0 + 0.15)
    release_launch()


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
