#!/bin/bash
# Launcher WiFi stack — one command on the Pi.
#
#   sudo bash setup/wifi_stack.sh on     # turn off old WiFi, start Launcher AP
#   sudo bash setup/wifi_stack.sh off    # stop AP, allow normal WiFi again
#   sudo bash setup/wifi_stack.sh status # show what is running

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CMD="${1:-on}"

case "$CMD" in
  on|start|up)
    exec bash "$SCRIPT_DIR/wifi_stack_on.sh"
    ;;
  off|stop|down)
    exec bash "$SCRIPT_DIR/wifi_stack_off.sh"
    ;;
  status)
    echo "=== WiFi stack status ==="
    systemctl is-active hostapd 2>/dev/null && echo "hostapd: active" || echo "hostapd: inactive"
    systemctl is-active dnsmasq 2>/dev/null && echo "dnsmasq: active" || echo "dnsmasq: inactive"
    systemctl is-active launcher 2>/dev/null && echo "launcher: active" || echo "launcher: inactive"
    systemctl is-active pigpiod 2>/dev/null && echo "pigpiod: active" || echo "pigpiod: inactive"
    ip -4 addr show wlan0 2>/dev/null || echo "wlan0: not found"
    ;;
  *)
    echo "Usage: sudo bash $0 {on|off|status}"
    exit 1
    ;;
esac
