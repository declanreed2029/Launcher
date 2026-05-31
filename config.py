"""Launcher Pi — edit GPIO and battery settings here."""

# WiFi access point (also used by setup_wifi_ap.sh)
WIFI_SSID = "Launcher"
WIFI_PASSWORD = "Launcher"
WIFI_CHANNEL = 6

# Web server
WEB_HOST = "0.0.0.0"
WEB_PORT = 80

# Pan servo signal wire -> BCM GPIO (matches ESP32 default PAN_SERVO_GPIO 18)
SERVO_GPIO = 18
SERVO_MIN_PULSE_US = 500
SERVO_MAX_PULSE_US = 2500

PAN_MIN_DEG = -180
PAN_MAX_DEG = 180
TILT_MIN_DEG = 0
TILT_MAX_DEG = 180
MOVE_STEP_DEG = 5

# Battery monitor
# Options: "mcp3008", "ina219", "none"
BATTERY_BACKEND = "none"

# MCP3008 (SPI): connect VDD->3.3V, VREF->3.3V, AGND/DGND->GND, CLK/DOUT/DIN/CS
MCP3008_CHANNEL = 0  # 0-7
# Vbat = Vadc * divider ratio (same 2:1 divider as ESP32 project)
BATTERY_DIVIDER_RATIO = 2.0
# LiPo mapping (mV), same as ESP32 battery_monitor.c
BATTERY_EMPTY_MV = 3300
BATTERY_FULL_MV = 4200

# INA219 (I2C) — set BATTERY_BACKEND = "ina219" if using this instead
INA219_I2C_ADDRESS = 0x40
INA219_SHUNT_OHMS = 0.1
INA219_MAX_AMPS = 3.2
