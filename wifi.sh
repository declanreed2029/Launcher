#!/bin/bash
# Launcher — one command to turn WiFi AP + HUD on or off.
#
#   sudo bash wifi.sh on       # stop old WiFi, start Launcher AP + web server
#   sudo bash wifi.sh off      # stop AP, allow normal WiFi again
#   sudo bash wifi.sh status   # show what is running
#   sudo bash wifi.sh sync     # copy this folder -> /opt/launcher, then on
#
# Run from: ~/projects/Launcher   (or anywhere you cloned the repo)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/launcher"
CMD="${1:-on}"

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo: sudo bash wifi.sh $CMD"
  exit 1
fi

sync_to_opt() {
  echo "=== Syncing ${ROOT} -> ${INSTALL_DIR} ==="
  mkdir -p "$INSTALL_DIR"
  rsync -a --exclude '__pycache__' --exclude '.venv' "${ROOT}/" "${INSTALL_DIR}/"
  if [[ -d "${ROOT}/assets" ]]; then
    mkdir -p "${INSTALL_DIR}/assets"
    rsync -a "${ROOT}/assets/" "${INSTALL_DIR}/assets/"
  fi
  chown -R "${SUDO_USER:-dtcteam2}:${SUDO_USER:-dtcteam2}" "$INSTALL_DIR"
  echo "Sync done."
}

ensure_venv() {
  if [[ ! -x "${INSTALL_DIR}/.venv/bin/python" ]]; then
    echo "=== Creating Python venv in ${INSTALL_DIR} ==="
    sudo -u "${SUDO_USER:-dtcteam2}" python3 -m venv "${INSTALL_DIR}/.venv"
    sudo -u "${SUDO_USER:-dtcteam2}" "${INSTALL_DIR}/.venv/bin/pip" install --upgrade pip
    sudo -u "${SUDO_USER:-dtcteam2}" "${INSTALL_DIR}/.venv/bin/pip" install -r "${INSTALL_DIR}/requirements.txt"
  fi
}

ensure_launcher_service() {
  if [[ ! -f /etc/systemd/system/launcher.service ]]; then
    echo "=== Creating launcher.service ==="
    tee /etc/systemd/system/launcher.service > /dev/null <<EOF
[Unit]
Description=Launcher HUD web server
After=network.target pigpiod.service
Wants=pigpiod.service

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/.venv/bin/python ${INSTALL_DIR}/server.py
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable launcher
  fi
}

stack_on() {
  sed -i 's/\r$//' "${ROOT}/setup/wifi_stack_on.sh" "${ROOT}/setup/wifi_stack_off.sh" 2>/dev/null || true
  sync_to_opt
  ensure_venv
  ensure_launcher_service
  bash "${ROOT}/setup/wifi_stack_on.sh"
}

stack_off() {
  sed -i 's/\r$//' "${ROOT}/setup/wifi_stack_off.sh" 2>/dev/null || true
  bash "${ROOT}/setup/wifi_stack_off.sh"
}

stack_status() {
  bash "${ROOT}/setup/wifi_stack.sh" status
  echo ""
  systemctl is-active launcher 2>/dev/null && echo "launcher service: active" || echo "launcher service: inactive"
}

case "$CMD" in
  on|start|up)
    stack_on
    ;;
  off|stop|down)
    stack_off
    ;;
  sync)
    sync_to_opt
    ensure_venv
    ensure_launcher_service
    echo "Synced. Run: sudo bash wifi.sh on"
    ;;
  status)
    stack_status
    ;;
  *)
    echo "Usage: sudo bash wifi.sh {on|off|status|sync}"
    exit 1
    ;;
esac
