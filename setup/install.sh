#!/bin/bash
# Install Python deps, pigpio, and systemd service for Launcher HUD
# Run on the Pi: sudo bash setup/install.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
INSTALL_DIR="/opt/launcher"
SERVICE_USER="${SUDO_USER:-pi}"

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo bash $0"
  exit 1
fi

echo "Installing system packages..."
apt-get update
apt-get install -y python3 python3-pip python3-venv rsync git make

install_pigpio() {
  if apt-get install -y pigpio 2>/dev/null; then
    echo "Installed pigpio from apt."
    return 0
  fi

  echo "pigpio not in apt — building from source..."
  build_dir="$(mktemp -d)"
  git clone --depth 1 https://github.com/joan2937/pigpio.git "$build_dir"
  make -C "$build_dir"
  make -C "$build_dir" install
  rm -rf "$build_dir"
  ldconfig

  if [[ ! -f /etc/systemd/system/pigpiod.service ]]; then
    cat > /etc/systemd/system/pigpiod.service <<'EOF'
[Unit]
Description=pigpio daemon
After=network.target

[Service]
Type=forking
ExecStart=/usr/local/bin/pigpiod
ExecStop=/bin/kill -s TERM $MAINPID
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  fi
}

install_pigpio
systemctl daemon-reload
systemctl enable pigpiod
systemctl start pigpiod

echo "Copying project to ${INSTALL_DIR}..."
mkdir -p "$INSTALL_DIR"
rsync -a --exclude '__pycache__' --exclude '.venv' "$PROJECT_DIR/" "$INSTALL_DIR/"
chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"

echo "Creating virtualenv..."
sudo -u "$SERVICE_USER" python3 -m venv "$INSTALL_DIR/.venv"
sudo -u "$SERVICE_USER" "$INSTALL_DIR/.venv/bin/pip" install --upgrade pip
sudo -u "$SERVICE_USER" "$INSTALL_DIR/.venv/bin/pip" install -r "$INSTALL_DIR/requirements.txt"

cat > /etc/systemd/system/launcher.service <<EOF
[Unit]
Description=Launcher HUD web server
After=network.target pigpiod.service hostapd.service
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
systemctl enable launcher.service

echo ""
echo "Install complete."
echo ""
echo "Next steps:"
echo "  1. Copy Intro.mp4 to ${INSTALL_DIR}/assets/Intro.mp4"
echo "  2. Edit ${INSTALL_DIR}/config.py (GPIO, battery backend)"
echo "  3. sudo bash ${INSTALL_DIR}/setup/setup_wifi_ap.sh   (if not done yet)"
echo "  4. sudo reboot"
echo "  5. Connect to WiFi 'Launcher', open http://192.168.4.1"
echo ""
echo "Manual start (test): sudo ${INSTALL_DIR}/.venv/bin/python ${INSTALL_DIR}/server.py"
