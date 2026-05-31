#!/bin/bash
# Configure Raspberry Pi as WiFi access point "Launcher" / "Launcher"
# Run on the Pi: sudo bash setup/setup_wifi_ap.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

SSID="Launcher"
PASS="Launcher"
CHANNEL=6

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo bash $0"
  exit 1
fi

echo "Installing hostapd and dnsmasq..."
apt-get update
apt-get install -y hostapd dnsmasq

systemctl stop hostapd 2>/dev/null || true
systemctl stop dnsmasq 2>/dev/null || true
systemctl unmask hostapd 2>/dev/null || true

cat > /etc/hostapd/hostapd.conf <<EOF
interface=wlan0
driver=nl80211
ssid=${SSID}
hw_mode=g
channel=${CHANNEL}
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

cat > /etc/dnsmasq.conf <<EOF
interface=wlan0
dhcp-range=192.168.4.2,192.168.4.20,255.255.255.0,24h
domain=local
address=/launcher.local/192.168.4.1
EOF

# Static IP for AP mode on wlan0
if ! grep -q "# launcher-ap" /etc/dhcpcd.conf 2>/dev/null; then
  cat >> /etc/dhcpcd.conf <<'EOF'

# launcher-ap
interface wlan0
    static ip_address=192.168.4.1/24
    nohook wpa_supplicant
EOF
fi

if [[ -f /etc/wpa_supplicant/wpa_supplicant.conf ]]; then
  if ! grep -q "launcher-ap-disable" /etc/wpa_supplicant/wpa_supplicant.conf; then
    echo "# launcher-ap-disable - hostapd owns wlan0" >> /etc/wpa_supplicant/wpa_supplicant.conf
  fi
fi

systemctl enable hostapd
systemctl enable dnsmasq

echo ""
echo "WiFi AP configured:"
echo "  SSID:     ${SSID}"
echo "  Password: ${PASS}"
echo "  Pi IP:    192.168.4.1"
echo ""
echo "Reboot to apply: sudo reboot"
echo "After reboot, connect to WiFi and open http://192.168.4.1"
