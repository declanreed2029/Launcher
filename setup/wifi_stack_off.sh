#!/bin/bash
# Stop Launcher AP stack and release wlan0 from AP mode.
# Run on Pi: sudo bash setup/wifi_stack_off.sh

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo bash $0"
  exit 1
fi

WLAN="${WLAN_INTERFACE:-wlan0}"

echo "=== Stopping Launcher WiFi stack ==="

systemctl stop hostapd 2>/dev/null || true
systemctl stop dnsmasq 2>/dev/null || true
systemctl disable hostapd 2>/dev/null || true
systemctl disable dnsmasq 2>/dev/null || true

# Remove static AP address
ip addr flush dev "$WLAN" 2>/dev/null || true

# Let NetworkManager manage WiFi again (if installed)
if command -v nmcli >/dev/null 2>&1; then
  nmcli device set "$WLAN" managed yes 2>/dev/null || true
  nmcli radio wifi on 2>/dev/null || true
fi

systemctl start wpa_supplicant 2>/dev/null || true
systemctl start NetworkManager 2>/dev/null || true
systemctl start dhcpcd 2>/dev/null || true

echo "Done. wlan0 released — you can join a normal WiFi network again."
echo "Reboot if WiFi still acts odd: sudo reboot"
