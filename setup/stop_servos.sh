#!/bin/bash
# Force all Launcher servos off (GPIO 18 pan, 19 tilt, 20 launch).
# Run: sudo bash setup/stop_servos.sh

set -euo pipefail

PAN_GPIO="${PAN_SERVO_GPIO:-18}"
TILT_GPIO="${TILT_SERVO_GPIO:-19}"
LAUNCH_GPIO="${LAUNCH_SERVO_GPIO:-20}"

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo bash $0"
  exit 1
fi

echo "=== Force stopping Launcher servos ==="

systemctl stop launcher 2>/dev/null || true
pkill -f '[s]erver.py' 2>/dev/null || true
pkill -f '/opt/launcher.*python' 2>/dev/null || true
sleep 0.5

if ! systemctl is-active --quiet pigpiod 2>/dev/null; then
  systemctl start pigpiod 2>/dev/null || pigpiod 2>/dev/null || true
  sleep 0.5
fi

release_with_pigs() {
  if ! command -v pigs >/dev/null 2>&1; then
    return 1
  fi
  for g in "$PAN_GPIO" "$TILT_GPIO" "$LAUNCH_GPIO"; do
    pigs SERVO "$g" 0 2>/dev/null || pigs p "$g" 0 2>/dev/null || true
  done
  return 0
}

release_with_python() {
  local py=""
  for candidate in \
    /opt/launcher/.venv/bin/python3 \
    /home/dtcteam2/Launcher/.venv/bin/python3 \
    python3; do
    if [[ -x "$candidate" ]] || command -v "$candidate" >/dev/null 2>&1; then
      py="$candidate"
      break
    fi
  done
  if [[ -z "$py" ]]; then
    return 1
  fi
  "$py" <<'PY'
import pigpio
pi = pigpio.pi()
if not pi.connected:
    raise SystemExit("pigpio not connected")
for g in (18, 19, 20):
    pi.set_servo_pulsewidth(g, 0)
pi.stop()
print("PWM released on GPIO 18, 19, 20")
PY
}

if release_with_pigs; then
  echo "Released PWM via pigs."
elif release_with_python; then
  echo "Released PWM via Python/pigpio."
else
  echo "WARNING: could not release PWM — is pigpio installed?"
fi

systemctl stop pigpiod 2>/dev/null || true
killall pigpiod 2>/dev/null || true

echo "Done. Servos should be quiet."
echo "If they still buzz, disconnect servo signal wires or power."
