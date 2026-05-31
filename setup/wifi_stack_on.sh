#!/bin/bash
# Turn OFF old WiFi client mode, turn ON Launcher access point + services.
# Run on Pi: sudo bash setup/wifi_stack_on.sh
#
# After this: connect phone/laptop to WiFi "Launcher" (password Launcher)
#              open http://192.168.4.1

set -euo pipefail

SSID="${WIFI_SSID:-Launcher}"
PASS="${WIFI_PASSWORD:-Launcher}"
CHANNEL="${WIFI_CHANNEL:-6}"
WLAN="${WLAN_INTERFACE:-wlan0}"
AP_IP="192.168.4.1/24"

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo bash $0"
  exit 1
fi

echo "=== Launcher WiFi stack ON ==="

# --- 1. Install AP packages if missing ---
if ! command -v hostapd >/dev/null 2>&1 || ! command -v dnsmasq >/dev/null 2>&1; then
  echo "Installing hostapd and dnsmasq..."
  apt-get update
  apt-get install -y hostapd dnsmasq
fi

# --- 2. Stop anything that fights for wlan0 ---
echo "Stopping previous WiFi / network managers on ${WLAN}..."

systemctl stop wpa_supplicant 2>/dev/null || true
systemctl stop wpa_supplicant@*.service 2>/dev/null || true
systemctl stop dhcpcd 2>/dev/null || true
systemctl stop NetworkManager 2>/dev/null || true

# NetworkManager: do not manage wlan0 while we run AP
if command -v nmcli >/dev/null 2>&1; then
  nmcli device set "$WLAN" managed no 2>/dev/null || true
  nmcli device disconnect "$WLAN" 2>/dev/null || true
fi

# Kill leftover processes on wlan0
pkill -f "wpa_supplicant.*${WLAN}" 2>/dev/null || true
sleep 1

# --- 3. Unblock WiFi radio ---
rfkill unblock wifi 2>/dev/null || true
ip link set "$WLAN" up

# --- 4. Write hostapd config ---
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

# Debian/Raspberry Pi OS: point hostapd at our config
if [[ -f /etc/default/hostapd ]]; then
  sed -i 's|^#*DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd
  grep -q '^DAEMON_CONF=' /etc/default/hostapd || \
    echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' >> /etc/default/hostapd
fi

# --- 5. Write dnsmasq config (DHCP for clients) ---
cat > /etc/dnsmasq.conf <<EOF
interface=${WLAN}
bind-interfaces
dhcp-range=192.168.4.2,192.168.4.20,255.255.255.0,24h
domain=local
address=/launcher.local/${AP_IP%/*}
EOF

# --- 6. Static IP on wlan0 (AP gateway) ---
echo "Setting ${WLAN} to ${AP_IP}..."
ip addr flush dev "$WLAN" 2>/dev/null || true
ip addr add "${AP_IP}" dev "$WLAN"

# Optional: persist in dhcpcd if you use it (not used while AP runs)
if [[ -f /etc/dhcpcd.conf ]] && ! grep -q "# launcher-ap" /etc/dhcpcd.conf; then
  cat >> /etc/dhcpcd.conf <<EOF

# launcher-ap
interface ${WLAN}
    static ip_address=${AP_IP}
    nohook wpa_supplicant
EOF
fi

# --- 7. Enable and start AP services ---
systemctl unmask hostapd 2>/dev/null || true
systemctl enable hostapd dnsmasq
systemctl restart dnsmasq
systemctl restart hostapd

sleep 2

if ! systemctl is-active --quiet hostapd; then
  echo ""
  echo "ERROR: hostapd failed to start. Last log lines:"
  journalctl -u hostapd -n 15 --no-pager
  echo ""
  echo "Try: sudo reboot   then run this script again."
  exit 1
fi

# --- 8. Start pigpio + Launcher web server ---
systemctl enable pigpiod 2>/dev/null || true
systemctl start pigpiod 2>/dev/null || true
systemctl enable launcher 2>/dev/null || true
systemctl start launcher 2>/dev/null || true

echo ""
echo "============================================"
echo "  Launcher WiFi is ON"
echo "  SSID:     ${SSID}"
echo "  Password: ${PASS}"
echo "  Pi IP:    ${AP_IP%/*}"
echo "  Browser:  http://${AP_IP%/*}"
echo "============================================"
echo ""
systemctl is-active --quiet hostapd && echo "  hostapd:  running" || echo "  hostapd:  FAILED"
systemctl is-active --quiet dnsmasq && echo "  dnsmasq:  running" || echo "  dnsmasq:  FAILED"
systemctl is-active --quiet launcher 2>/dev/null && echo "  launcher: running" || echo "  launcher: not installed (run setup/install.sh)"
echo ""
echo "SSH over AP: ssh dtcteam2@${AP_IP%/*}  (from a device on Launcher WiFi)"
echo "To turn AP off: sudo bash setup/wifi_stack_off.sh"
