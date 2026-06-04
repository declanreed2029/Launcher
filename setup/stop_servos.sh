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
  PAN_GPIO="$PAN_GPIO" TILT_GPIO="$TILT_GPIO" LAUNCH_GPIO="$LAUNCH_GPIO" "$py" <<'PY'
import os
import pigpio

pins = (
    int(os.environ.get("PAN_GPIO", 18)),
    int(os.environ.get("TILT_GPIO", 19)),
    int(os.environ.get("LAUNCH_GPIO", 20)),
)
pi = pigpio.pi()
if not pi.connected:
    raise SystemExit("pigpio not connected")
for g in pins:
    pi.set_servo_pulsewidth(g, 0)
    pi.set_mode(g, pigpio.INPUT)
    pi.set_pull_up_down(g, pigpio.PUD_OFF)
pi.stop()
print("PWM off + pins released:", ", ".join(str(p) for p in pins))
PY
}

if release_with_pigs; then
  echo "Released PWM via pigs."
  for g in "$PAN_GPIO" "$TILT_GPIO" "$LAUNCH_GPIO"; do
    pigs mod "$g" r 2>/dev/null || true
  done
elif release_with_python; then
  echo "Released PWM via Python/pigpio."
else
  echo "WARNING: could not release PWM — is pigpio installed?"
fi

systemctl stop pigpiod 2>/dev/null || true
killall pigpiod 2>/dev/null || true

echo ""
echo "Done. If a servo STILL moves, it is almost certainly:"
echo "  1) Signal wire on the WRONG GPIO (not 18/19/20), or"
echo "  2) Not controlled by the Pi (other board / wiring), or"
echo "  3) Power still on — unplug that servo's SIGNAL wire to test."
echo ""
echo "Which one moves?  Pan (left/right)=GPIO18  Tilt=19  Launch=20"
