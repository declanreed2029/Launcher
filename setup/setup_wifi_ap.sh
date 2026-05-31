#!/bin/bash
# One-time: install hostapd/dnsmasq config only (does NOT enable AP on boot).
# Run: sudo bash setup/setup_wifi_ap.sh
# Then: sudo bash wifi.sh on

set -euo pipefail

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
systemctl disable hostapd 2>/dev/null || true
systemctl disable dnsmasq 2>/dev/null || true
systemctl unmask hostapd 2>/dev/null || true

mkdir -p /etc/hostapd /etc/launcher
rm -f /etc/launcher/ap-on-boot

cat > /etc/hostapd/hostapd.conf <<EOF
interface=wlan0
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
fi

cat > /etc/dnsmasq.conf <<EOF
interface=wlan0
bind-interfaces
dhcp-range=192.168.4.2,192.168.4.20,255.255.255.0,24h
domain=local
address=/launcher.local/192.168.4.1
EOF

echo ""
echo "Config installed. AP is disabled on boot (safe for Pi Connect)."
echo ""
echo "Start Launcher WiFi now:  sudo bash wifi.sh on"
echo "Never use auto-boot AP unless you want: sudo bash wifi.sh on --boot"
