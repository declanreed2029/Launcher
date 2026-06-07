#!/bin/bash
# Start pigpiod + launcher and verify servos initialized.
# Run: sudo bash setup/start_servos.sh

set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/launcher}"

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo bash $0"
  exit 1
fi

echo "=== Starting servo stack ==="

if ! command -v pigpiod >/dev/null 2>&1; then
  echo "ERROR: pigpiod not installed. Run: sudo bash setup/install.sh"
  exit 1
fi

systemctl stop launcher 2>/dev/null || true
systemctl restart pigpiod 2>/dev/null || systemctl start pigpiod 2>/dev/null || pigpiod 2>/dev/null || true

for _ in $(seq 1 24); do
  systemctl is-active --quiet pigpiod 2>/dev/null && break
  pgrep -x pigpiod >/dev/null 2>&1 && break
  sleep 0.25
done

if ! systemctl is-active --quiet pigpiod 2>/dev/null && ! pgrep -x pigpiod >/dev/null 2>&1; then
  echo "ERROR: pigpiod did not start."
  exit 1
fi

if [[ ! -x "${INSTALL_DIR}/.venv/bin/python" ]]; then
  echo "ERROR: ${INSTALL_DIR}/.venv missing. Run: sudo bash wifi.sh sync"
  exit 1
fi

systemctl restart launcher 2>/dev/null || systemctl start launcher 2>/dev/null || {
  echo "launcher.service missing — starting server directly..."
  pkill -f '[s]erver.py' 2>/dev/null || true
  cd "$INSTALL_DIR"
  nohup "${INSTALL_DIR}/.venv/bin/python" "${INSTALL_DIR}/server.py" >/tmp/launcher.log 2>&1 &
  sleep 2
}

for attempt in 1 2 3; do
  sleep 2
  if journalctl -u launcher -n 60 --no-pager 2>/dev/null | grep -q "Servos ready"; then
    echo "Servos ready (attempt ${attempt})."
    exit 0
  fi
  if [[ -f /tmp/launcher.log ]] && grep -q "Servos ready" /tmp/launcher.log 2>/dev/null; then
    echo "Servos ready (direct run)."
    exit 0
  fi
  echo "Waiting for servos (attempt ${attempt}/3)..."
  systemctl restart launcher 2>/dev/null || true
done

echo "WARNING: launcher running but 'Servos ready' not in logs."
echo "  journalctl -u launcher -n 30 --no-pager"
exit 1
