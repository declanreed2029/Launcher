"""Launcher Pi — edit GPIO and battery settings here."""

# WiFi access point (also used by setup_wifi_ap.sh)
WIFI_SSID = "Launcher"
WIFI_PASSWORD = "Launcher"
WIFI_CHANNEL = 6

# Web server
WEB_HOST = "0.0.0.0"
WEB_PORT = 80

# Servo signal wires -> BCM GPIO (BCM numbering, not physical pin #)
PAN_SERVO_GPIO = 18   # left / right — physical pin 12
TILT_SERVO_GPIO = 19  # up / down — physical pin 35
LAUNCH_SERVO_GPIO = 20  # launch — physical pin 38
# If tilt/launch don't move but pan does, swap tilt/launch GPIOs here and re-sync.
SERVO_GPIO = PAN_SERVO_GPIO  # alias for older configs

# Launch sequence (Lock → 3s countdown → 90° hold → rest → cooldown display)
LAUNCH_ARM_SEC = 10
LAUNCH_COUNTDOWN_SEC = 3
LAUNCH_HOLD_SEC = 0.5
LAUNCH_COOLDOWN_SEC = 30
LAUNCH_REST_DEG = 0
LAUNCH_FIRE_DEG = 92
# True = fire ±LAUNCH_FIRE_DEG from rest the other way (rest servo at FIRE_DEG, fire at 0).
LAUNCH_INVERT = True

SERVO_MIN_PULSE_US = 500
SERVO_MAX_PULSE_US = 2500
# Stop PWM after each move so servos do not buzz/hunt while idle (ms)
SERVO_RELEASE_MS = 400
SERVO_TILT_RELEASE_MS = 1200  # tilt often needs longer drive than pan
LAUNCH_RETURN_MS = 1500  # ms to drive to rest before PWM off (no sustained hold)

PAN_MIN_DEG = -180
PAN_MAX_DEG = 180
TILT_MIN_DEG = 0
TILT_MAX_DEG = 180
MOVE_STEP_DEG = 5

# If servos stop after a few moves, pigpiod may have died from brownout — auto-restart it
PIGPIO_AUTO_RESTART = True
PIGPIO_RESTART_COOLDOWN_SEC = 5

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
