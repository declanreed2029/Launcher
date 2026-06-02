#!/bin/bash
# Launcher — WiFi AP + HUD control
#
#   sudo bash wifi.sh on          # Start Launcher AP now (stops after reboot)
#   sudo bash wifi.sh on --boot   # Start AP now AND after every reboot
#   sudo bash wifi.sh off         # Stop AP, disable auto-start, use hotspot again
#   sudo bash wifi.sh status      # What is running
#   sudo bash wifi.sh sync        # Copy project -> /opt/launcher
#
# Typical use:
#   Demo day:     sudo bash wifi.sh on
#   Dev / Connect: sudo bash wifi.sh off

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/launcher"
CMD="${1:-}"
FLAG="${2:-}"

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo: sudo bash wifi.sh <command>"
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
  fi
}

stack_on() {
  sed -i 's/\r$//' "${ROOT}/setup/wifi_stack"*.sh 2>/dev/null || true
  sync_to_opt
  ensure_venv
  ensure_launcher_service
  if [[ "$FLAG" == "--boot" ]]; then
    bash "${ROOT}/setup/wifi_stack_on.sh" --boot
  else
    bash "${ROOT}/setup/wifi_stack_on.sh"
  fi
}

stack_off() {
  sed -i 's/\r$//' "${ROOT}/setup/wifi_stack_off.sh" 2>/dev/null || true
  bash "${ROOT}/setup/wifi_stack_off.sh"
}

stack_status() {
  echo "=== Launcher WiFi status ==="
  if [[ -f /etc/launcher/ap-on-boot ]]; then
    echo "Boot:     AP will auto-start on reboot"
  else
    echo "Boot:     AP will NOT auto-start (good for Pi Connect)"
  fi
  systemctl is-active hostapd 2>/dev/null && echo "hostapd:  active" || echo "hostapd:  inactive"
  systemctl is-active dnsmasq 2>/dev/null && echo "dnsmasq:  active" || echo "dnsmasq:  inactive"
  systemctl is-active pigpiod 2>/dev/null && echo "pigpiod:  active" || echo "pigpiod:  inactive"
  systemctl is-active launcher 2>/dev/null && echo "launcher: active" || echo "launcher: inactive"
  ip -4 addr show wlan0 2>/dev/null | grep -oP 'inet \K[0-9.]+' | head -1 | xargs -I{} echo "wlan0 IP: {}" || true
}

case "$CMD" in
  on|start|up)
    stack_on
    ;;
  off|stop|down|client|hotspot)
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
    echo "Usage:"
    echo "  sudo bash wifi.sh on           # Launcher AP now only"
    echo "  sudo bash wifi.sh on --boot    # Launcher AP now + every reboot"
    echo "  sudo bash wifi.sh off          # Stop AP, use personal hotspot"
    echo "  sudo bash wifi.sh status"
    echo "  sudo bash wifi.sh sync"
    exit 1
    ;;
esac
