#!/bin/bash
# Install/refresh pigpiod systemd unit with auto-restart on failure (brownout recovery).
# Run: sudo bash setup/ensure_pigpiod.sh

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo bash $0"
  exit 1
fi

PIGPIOD_BIN="$(command -v pigpiod || true)"
if [[ -z "$PIGPIOD_BIN" ]]; then
  echo "ERROR: pigpiod not found. Run: sudo bash setup/install.sh"
  exit 1
fi

echo "=== Ensuring pigpiod.service (${PIGPIOD_BIN}) ==="

tee /etc/systemd/system/pigpiod.service > /dev/null <<EOF
[Unit]
Description=pigpio daemon (Launcher servo GPIO)
After=network.target
StartLimitIntervalSec=120
StartLimitBurst=10

[Service]
Type=forking
ExecStart=${PIGPIOD_BIN}
ExecStop=/bin/kill -s TERM \$MAINPID
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable pigpiod
systemctl restart pigpiod || systemctl start pigpiod

echo "pigpiod.service installed with Restart=on-failure"
systemctl is-active pigpiod && echo "pigpiod: active" || echo "pigpiod: FAILED"
