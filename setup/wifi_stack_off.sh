#!/bin/bash
# Stop Launcher AP and return Pi to normal WiFi (personal hotspot / home router).
# Run on Pi: sudo bash wifi.sh off

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo bash $0"
  exit 1
fi

WLAN="${WLAN_INTERFACE:-wlan0}"

echo "=== Stopping Launcher WiFi stack ==="

echo "Stopping servo stack (launcher HUD + pigpiod)..."
systemctl stop launcher 2>/dev/null || true
systemctl stop pigpiod 2>/dev/null || true
systemctl disable launcher pigpiod 2>/dev/null || true

systemctl stop hostapd 2>/dev/null || true
systemctl stop dnsmasq 2>/dev/null || true
systemctl disable hostapd 2>/dev/null || true
systemctl disable dnsmasq 2>/dev/null || true

rm -f /etc/launcher/ap-on-boot 2>/dev/null || true

ip addr flush dev "$WLAN" 2>/dev/null || true
ip link set "$WLAN" up 2>/dev/null || true

rfkill unblock wifi 2>/dev/null || true

if command -v nmcli >/dev/null 2>&1; then
  echo "Re-enabling NetworkManager on ${WLAN}..."
  nmcli device set "$WLAN" managed yes 2>/dev/null || true
  nmcli radio wifi on 2>/dev/null || true
  systemctl start NetworkManager 2>/dev/null || true
  sleep 2
  # Try to reconnect to last saved network
  nmcli device wifi connect "$(nmcli -t -f NAME connection show --active 2>/dev/null | head -1)" 2>/dev/null || \
    nmcli device wifi list 2>/dev/null | head -5
  echo ""
  echo "To join your hotspot manually:"
  echo "  nmcli device wifi list"
  echo "  nmcli device wifi connect \"YOUR_HOTSPOT_NAME\" password \"YOUR_PASSWORD\""
else
  systemctl start wpa_supplicant 2>/dev/null || true
  systemctl start dhcpcd 2>/dev/null || true
fi

echo ""
echo "Done. Launcher AP is off and will NOT start on reboot."
echo "  - Use Raspberry Pi Connect / SSH on your normal network again."
echo "  - If WiFi is stuck: sudo reboot"
echo ""
echo "Start Launcher AP again later: sudo bash wifi.sh on"
