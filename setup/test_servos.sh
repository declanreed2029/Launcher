#!/bin/bash
# Pulse each servo GPIO directly — bypasses the HUD to isolate wiring vs software.
# Run on Pi: sudo bash setup/test_servos.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source <(grep -E '^(PAN|TILT|LAUNCH)_SERVO_GPIO' "${ROOT}/config.py" | sed 's/ = /=/')

PAN_GPIO="${PAN_SERVO_GPIO:-18}"
TILT_GPIO="${TILT_SERVO_GPIO:-19}"
LAUNCH_GPIO="${LAUNCH_SERVO_GPIO:-20}"

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo bash $0"
  exit 1
fi

if ! command -v pigs >/dev/null 2>&1; then
  echo "ERROR: pigs not found — install pigpio: sudo bash setup/install.sh"
  exit 1
fi

systemctl start pigpiod 2>/dev/null || pigpiod 2>/dev/null || true
sleep 0.5

pulse_gpio() {
  local name="$1"
  local gpio="$2"
  echo ""
  echo "=== ${name} (GPIO ${gpio}) — center 1500us, then min 500us, then max 2500us ==="
  for us in 1500 500 2500 1500; do
    echo "  pulse ${us}us..."
    if ! pigs SERVO "${gpio}" "${us}"; then
      echo "  ERROR: pigs SERVO ${gpio} ${us} failed"
      return 1
    fi
    sleep 1.2
  done
  pigs SERVO "${gpio}" 0 2>/dev/null || true
  echo "  ${name}: pulses sent — did the servo move?"
}

echo "Launcher servo GPIO test"
echo "  Pan GPIO${PAN_GPIO}  Tilt GPIO${TILT_GPIO}  Launch GPIO${LAUNCH_GPIO}"
echo ""
echo "Watch each servo while this runs. If pan moves but tilt/launch do not,"
echo "check signal wires on GPIO ${TILT_GPIO} and ${LAUNCH_GPIO} (pins 35 and 38)."
echo ""

pulse_gpio "Pan (left/right)" "${PAN_GPIO}"
pulse_gpio "Tilt (up/down)" "${TILT_GPIO}"
pulse_gpio "Launch" "${LAUNCH_GPIO}"

echo ""
echo "=== Done ==="
echo "If only one axis failed here, it is wiring or that servo — not the HUD."
echo "If all three moved here but HUD does not, restart: sudo bash setup/start_servos.sh"
