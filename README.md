# Launcher Pi

Raspberry Pi WiFi access point + HUD web control (ported from the ESP32 `softAP_web_control` project).

## What it does

- Broadcasts WiFi **Launcher** / password **Launcher**
- Serves the same HUD webpage at **http://192.168.4.1**
- Plays **Intro.mp4** after the boot sequence
- **Left / Right** D-pad buttons move the pan servo (GPIO 18 by default)
- **Battery %** from MCP3008 voltage divider or INA219 (optional)

## Hardware

| Function | Default | Notes |
|----------|---------|-------|
| Pan servo signal | GPIO 18 (BCM) | 5V + GND from external supply recommended |
| Battery sense | MCP3008 CH0 | Same 2:1 divider as ESP32 (3.3V max at ADC pin) |
| MCP3008 SPI | CE0, MOSI, MISO, SCLK | Enable SPI in `raspi-config` |

Set `BATTERY_BACKEND = "none"` in `config.py` if no battery sensor is wired.

## Transfer files to the Pi

From **Windows PowerShell** (replace `pi@192.168.x.x` with your Pi’s current IP):

```powershell
# Copy the whole project folder
scp -r "C:\Northwestern\Research\pi_launcher" pi@192.168.x.x:~/

# Copy the intro video separately (can be large)
scp "C:\Northwestern\2025-2026\DTC2\Intro.mp4" pi@192.168.x.x:~/pi_launcher/static/Intro.mp4
```

Alternative with **WinSCP** or **FileZilla**: connect via SFTP and drag `pi_launcher` and `Intro.mp4` into `~/pi_launcher/static/`.

## Install on the Pi

SSH into the Pi, then:

```bash
cd ~/pi_launcher
chmod +x setup/*.sh
sudo bash setup/install.sh
sudo bash setup/setup_wifi_ap.sh
sudo reboot
```

After reboot:

1. Connect phone/laptop to WiFi **Launcher** (password **Launcher**)
2. Open **http://192.168.4.1**

## Quick test (before AP setup)

```bash
cd ~/pi_launcher
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
sudo pigpiod
sudo .venv/bin/python server.py
```

Then open `http://<pi-ip>:80` from a machine on the same network.

## API (same as ESP32)

| Endpoint | Description |
|----------|-------------|
| `GET /` | HUD webpage |
| `GET /Intro.mp4` | Intro video |
| `GET /cmd?move=left\|right\|up\|down` | Move pan/tilt |
| `GET /api/status` | JSON: `battery_percent`, `pan_deg`, `tilt_deg` |
