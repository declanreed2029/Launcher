#!/bin/bash
# Turn OFF old WiFi client mode, turn ON Launcher access point + services.
# Run on Pi: sudo bash setup/wifi_stack_on.sh
#           sudo bash setup/wifi_stack_on.sh --boot   # also start AP after every reboot
#
# Default (no --boot): AP runs until reboot or "wifi.sh off" — safe for Pi Connect / hotspot.

set -euo pipefail

SSID="${WIFI_SSID:-Launcher}"
PASS="${WIFI_PASSWORD:-Launcher}"
CHANNEL="${WIFI_CHANNEL:-6}"
WLAN="${WLAN_INTERFACE:-wlan0}"
AP_IP="192.168.4.1/24"
ENABLE_BOOT=0

if [[ "${1:-}" == "--boot" ]]; then
  ENABLE_BOOT=1
fi

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo bash $0 [--boot]"
  exit 1
fi

echo "=== Launcher WiFi stack ON ==="

if ! command -v hostapd >/dev/null 2>&1 || ! command -v dnsmasq >/dev/null 2>&1; then
  echo "Installing hostapd and dnsmasq..."
  apt-get update
  apt-get install -y hostapd dnsmasq
fi

echo "Stopping previous WiFi / network managers on ${WLAN}..."

systemctl stop wpa_supplicant 2>/dev/null || true
systemctl stop wpa_supplicant@"${WLAN}".service 2>/dev/null || true
systemctl stop dhcpcd 2>/dev/null || true
systemctl stop NetworkManager 2>/dev/null || true

if command -v nmcli >/dev/null 2>&1; then
  nmcli device set "$WLAN" managed no 2>/dev/null || true
  nmcli device disconnect "$WLAN" 2>/dev/null || true
fi

pkill -f "wpa_supplicant.*${WLAN}" 2>/dev/null || true
sleep 1

rfkill unblock wifi 2>/dev/null || true
ip link set "$WLAN" up

mkdir -p /etc/hostapd
cat > /etc/hostapd/hostapd.conf <<EOF
interface=${WLAN}
driver=nl80211
ssid=${SSID}
hw_mode=g
channel=${CHANNEL}
country_code=US
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=${PASS}
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP CCMP
rsn_pairwise=CCMP
EOF

if [[ -f /etc/default/hostapd ]]; then
  sed -i 's|^#*DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd
  grep -q '^DAEMON_CONF=' /etc/default/hostapd || \
    echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' >> /etc/default/hostapd
fi

cat > /etc/dnsmasq.conf <<EOF
interface=${WLAN}
bind-interfaces
dhcp-range=192.168.4.2,192.168.4.20,255.255.255.0,24h
domain=local
address=/launcher.local/${AP_IP%/*}
EOF

echo "Setting ${WLAN} to ${AP_IP}..."
ip addr flush dev "$WLAN" 2>/dev/null || true
ip addr add "${AP_IP}" dev "$WLAN"

systemctl unmask hostapd 2>/dev/null || true

if [[ "$ENABLE_BOOT" -eq 1 ]]; then
  mkdir -p /etc/launcher
  touch /etc/launcher/ap-on-boot
  systemctl enable hostapd dnsmasq
  echo "AP will start automatically on every boot."
else
  rm -f /etc/launcher/ap-on-boot 2>/dev/null || true
  systemctl disable hostapd dnsmasq 2>/dev/null || true
  echo "AP will NOT start on reboot (use: sudo bash wifi.sh on --boot to change)."
fi

systemctl restart dnsmasq
systemctl restart hostapd

sleep 2

if ! systemctl is-active --quiet hostapd; then
  echo ""
  echo "ERROR: hostapd failed to start. Last log lines:"
  journalctl -u hostapd -n 15 --no-pager
  exit 1
fi

echo "Starting servo stack (pigpiod + launcher HUD + pan/tilt/launch)..."
if ! command -v pigpiod >/dev/null 2>&1; then
  echo "Installing pigpio..."
  apt-get update
  apt-get install -y pigpio || true
  systemctl daemon-reload 2>/dev/null || true
fi

systemctl start pigpiod 2>/dev/null || true
for _ in $(seq 1 24); do
  systemctl is-active --quiet pigpiod && break
  sleep 0.25
done
if ! systemctl is-active --quiet pigpiod; then
  echo ""
  echo "ERROR: pigpiod is not running — servos will not work."
  echo "  Try: sudo bash setup/install.sh"
  echo "  Or:  sudo systemctl start pigpiod && sudo systemctl restart launcher"
  exit 1
fi

systemctl restart launcher 2>/dev/null || systemctl start launcher 2>/dev/null || true
sleep 2
if journalctl -u launcher -n 50 --no-pager 2>/dev/null | grep -q "Servos ready"; then
  echo "Servos initialized (pan, tilt, launch)."
else
  echo "WARNING: launcher running but servos may not be ready — restarting launcher..."
  systemctl restart launcher
  sleep 2
fi

if [[ "$ENABLE_BOOT" -eq 1 ]]; then
  systemctl enable pigpiod launcher 2>/dev/null || true
  echo "Servo stack will start automatically on every boot (with AP --boot)."
else
  systemctl disable pigpiod launcher 2>/dev/null || true
  echo "Servo stack will stop when you run: sudo bash wifi.sh off"
fi

echo ""
echo "============================================"
echo "  Launcher WiFi is ON (this session)"
echo "  SSID:     ${SSID}"
echo "  Password: ${PASS}"
echo "  Pi IP:    ${AP_IP%/*}"
echo "  Browser:  http://${AP_IP%/*}"
echo "============================================"
echo ""
systemctl is-active --quiet hostapd && echo "  hostapd:  running" || echo "  hostapd:  FAILED"
systemctl is-active --quiet dnsmasq && echo "  dnsmasq:  running" || echo "  dnsmasq:  FAILED"
systemctl is-active --quiet pigpiod 2>/dev/null && echo "  pigpiod:  running" || echo "  pigpiod:  inactive"
systemctl is-active --quiet launcher 2>/dev/null && echo "  launcher: running" || echo "  launcher: not installed"
if journalctl -u launcher -n 50 --no-pager 2>/dev/null | grep -q "Servos ready"; then
  echo "  servos:   ready (pan/tilt/launch)"
else
  echo "  servos:   check logs: journalctl -u launcher -n 20"
fi
echo ""
echo "Turn AP off (back to personal hotspot): sudo bash wifi.sh off"
echo "SSH on Launcher WiFi: ssh dtcteam2@${AP_IP%/*}"
