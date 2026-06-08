#!/bin/bash
# Launcher — WiFi AP + HUD control
#
#   sudo bash wifi.sh on          # Start Launcher AP now (stops after reboot)
#   sudo bash wifi.sh on --boot   # Start AP now AND after every reboot
#   sudo bash wifi.sh off         # Stop AP, disable auto-start, use hotspot again
#   sudo bash wifi.sh status      # What is running
#   sudo bash wifi.sh sync        # Copy project -> /opt/launcher
#   sudo bash wifi.sh servos-off  # Force PWM off immediately
#   sudo bash wifi.sh hud-on      # Start pigpiod + launcher only (no WiFi AP)
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
  echo "=== [sync] Copying ${ROOT} -> ${INSTALL_DIR} (large videos may take 1-2 min) ==="
  mkdir -p "$INSTALL_DIR"
  rsync -a --info=STATS2 --exclude '__pycache__' --exclude '.venv' "${ROOT}/" "${INSTALL_DIR}/" || \
    rsync -a --exclude '__pycache__' --exclude '.venv' "${ROOT}/" "${INSTALL_DIR}/"
  if [[ -d "${ROOT}/assets" ]]; then
    mkdir -p "${INSTALL_DIR}/assets"
    rsync -a "${ROOT}/assets/" "${INSTALL_DIR}/assets/" || true
  fi
  chown -R "${SUDO_USER:-dtcteam2}:${SUDO_USER:-dtcteam2}" "$INSTALL_DIR"
  echo "=== [sync] Done ==="
}

ensure_pigpio() {
  if command -v pigpiod >/dev/null 2>&1 \
     && { systemctl cat pigpiod.service &>/dev/null \
          || [[ -f /lib/systemd/system/pigpiod.service ]]; }; then
    return 0
  fi
  echo "=== Installing pigpio (required for servos) ==="
  apt-get update
  if apt-get install -y pigpio 2>/dev/null; then
    systemctl daemon-reload
    return 0
  fi
  echo "WARNING: pigpio package not found — run: sudo bash setup/install.sh"
  return 1
}

ensure_venv() {
  local req="${INSTALL_DIR}/requirements.txt"
  local marker="${INSTALL_DIR}/.venv/.deps_installed"
  if [[ ! -x "${INSTALL_DIR}/.venv/bin/python" ]]; then
    echo "=== [venv] Creating Python venv ==="
    sudo -u "${SUDO_USER:-dtcteam2}" python3 -m venv "${INSTALL_DIR}/.venv"
  fi
  if [[ -f "$marker" ]] && [[ "$req" -ot "$marker" ]]; then
    echo "=== [venv] Dependencies unchanged, skipping pip install ==="
    return 0
  fi
  echo "=== [venv] Installing Python packages (timeout 3 min) ==="
  timeout 180 sudo -u "${SUDO_USER:-dtcteam2}" "${INSTALL_DIR}/.venv/bin/pip" install --upgrade pip -q || true
  timeout 180 sudo -u "${SUDO_USER:-dtcteam2}" "${INSTALL_DIR}/.venv/bin/pip" install \
    -r "${INSTALL_DIR}/requirements.txt" -q
  touch "$marker"
  echo "=== [venv] Done ==="
}

_daemon_reload_safe() {
  echo "=== [service] systemctl daemon-reload (max 15s) ==="
  if command -v timeout >/dev/null 2>&1; then
    if timeout 15 systemctl daemon-reload; then
      echo "=== [service] daemon-reload OK ==="
      return 0
    fi
    echo "WARNING: daemon-reload timed out — continuing anyway"
    return 0
  fi
  systemctl daemon-reload &
  local pid=$!
  local i
  for i in $(seq 1 15); do
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "=== [service] daemon-reload OK ==="
      return 0
    fi
    sleep 1
  done
  kill "$pid" 2>/dev/null || true
  echo "WARNING: daemon-reload still running after 15s — continuing anyway"
}

ensure_launcher_service() {
  local svc="/etc/systemd/system/launcher.service"
  local tmp
  tmp="$(mktemp)"
  cat > "$tmp" <<EOF
[Unit]
Description=Launcher HUD web server (pan, tilt, launch servos)
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
  if [[ -f "$svc" ]] && cmp -s "$tmp" "$svc"; then
    echo "=== [service] launcher.service unchanged — skip daemon-reload ==="
    rm -f "$tmp"
    return 0
  fi
  echo "=== [service] Installing launcher.service ==="
  cp "$tmp" "$svc"
  rm -f "$tmp"
  _daemon_reload_safe
  echo "=== [service] Done ==="
}

stop_servos_now() {
  if [[ -f "${ROOT}/setup/stop_servos.sh" ]]; then
    bash "${ROOT}/setup/stop_servos.sh"
  else
    echo "=== Stopping servos (PWM off) ==="
    systemctl stop launcher 2>/dev/null || true
    timeout 15 systemctl restart pigpiod 2>/dev/null \
      || timeout 15 systemctl stop pigpiod 2>/dev/null || true
    sleep 0.5
    echo "Servos stopped."
  fi
}

stack_on() {
  echo "=== wifi.sh on: starting ==="
  sed -i 's/\r$//' "${ROOT}/setup/wifi_stack"*.sh 2>/dev/null || true
  stop_servos_now
  sync_to_opt
  echo "=== [pigpio] Checking pigpio ==="
  ensure_pigpio || true
  ensure_venv
  ensure_launcher_service
  echo "=== [wifi] Starting access point stack ==="
  if [[ "$FLAG" == "--boot" ]]; then
    bash "${ROOT}/setup/wifi_stack_on.sh" --boot
  else
    bash "${ROOT}/setup/wifi_stack_on.sh"
  fi
  echo "=== wifi.sh on: finished ==="
}

stack_off() {
  stop_servos_now
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
  if systemctl is-active --quiet launcher 2>/dev/null \
     && journalctl -u launcher -n 40 --no-pager 2>/dev/null | grep -q "Servos ready"; then
    echo "servos:   ready (pan GPIO18, tilt GPIO19, launch GPIO20)"
  elif systemctl is-active --quiet launcher 2>/dev/null; then
    echo "servos:   NOT READY — run: sudo systemctl restart launcher"
    echo "          logs: journalctl -u launcher -n 20"
  else
    echo "servos:   offline (start with: sudo bash wifi.sh on)"
  fi
  ip -4 addr show wlan0 2>/dev/null | grep -oP 'inet \K[0-9.]+' | head -1 | xargs -I{} echo "wlan0 IP: {}" || true
  if dmesg 2>/dev/null | grep -qiE 'under-voltage|Undervoltage detected'; then
    echo "power:    UNDER-VOLTAGE events in kernel log — use a stronger 5V supply"
    echo "          dmesg | grep -i voltage"
  fi
  restarts="$(curl -sf http://127.0.0.1/api/status 2>/dev/null | grep -oP '"pigpiod_restarts":\s*\K[0-9]+' || true)"
  if [[ -n "${restarts}" ]] && [[ "${restarts}" -gt 0 ]]; then
    echo "pigpiod:  auto-restarted ${restarts} time(s) this session (possible brownouts)"
  fi
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
  servos-off|stop-servos)
    stop_servos_now
    ;;
  hud-on|servos-on)
    sync_to_opt
    ensure_venv
    ensure_launcher_service
    bash "${ROOT}/setup/start_servos.sh"
    ;;
  status)
    stack_status
    ;;
  *)
    echo "Usage:"
    echo "  sudo bash wifi.sh on           # Launcher AP now only"
    echo "  sudo bash wifi.sh on --boot    # Launcher AP now + every reboot"
    echo "  sudo bash wifi.sh off          # Stop AP, use personal hotspot"
    echo "  sudo bash wifi.sh servos-off   # Force servos off now"
    echo "  sudo bash wifi.sh hud-on       # Servos + HUD only (skip WiFi AP)"
    echo "  sudo bash wifi.sh status"
    echo "  sudo bash wifi.sh sync"
    exit 1
    ;;
esac
