"""Battery voltage / percent — MCP3008 divider or INA219."""

from __future__ import annotations

import logging
import threading
import time

import config

log = logging.getLogger(__name__)

_lock = threading.Lock()
_cached_percent: int | None = None
_cached_voltage_mv: int | None = None
_reader = None


def _voltage_to_percent(voltage_mv: int) -> int:
    if voltage_mv <= config.BATTERY_EMPTY_MV:
        return 0
    if voltage_mv >= config.BATTERY_FULL_MV:
        return 100
    span = config.BATTERY_FULL_MV - config.BATTERY_EMPTY_MV
    return (voltage_mv - config.BATTERY_EMPTY_MV) * 100 // span


class _Mcp3008Reader:
    def __init__(self) -> None:
        import spidev

        self._spi = spidev.SpiDev()
        self._spi.open(0, 0)
        self._spi.max_speed_hz = 1350000
        self._spi.mode = 0

    def read_mv(self) -> int:
        channel = config.MCP3008_CHANNEL
        cmd = 0x18 | ((channel & 0x07) >> 2)
        bits = ((channel & 0x07) << 6) & 0xFF
        raw = self._spi.xfer2([cmd, bits, 0])
        value = ((raw[1] & 0x03) << 8) | raw[2]
        adc_mv = int(value * 3300 / 1023)
        return int(adc_mv * config.BATTERY_DIVIDER_RATIO)

    def close(self) -> None:
        self._spi.close()


class _Ina219Reader:
    def __init__(self) -> None:
        try:
            from ina219 import INA219
        except ImportError as exc:
            raise ImportError(
                "INA219 backend requires pi-ina219: pip install pi-ina219"
            ) from exc

        self._ina = INA219(config.INA219_SHUNT_OHMS, address=config.INA219_I2C_ADDRESS)
        self._ina.configure()

    def read_mv(self) -> int:
        return int(self._ina.voltage() * 1000)

    def close(self) -> None:
        pass


def _make_reader():
    backend = config.BATTERY_BACKEND.lower()
    if backend == "none":
        return None
    if backend == "mcp3008":
        return _Mcp3008Reader()
    if backend == "ina219":
        return _Ina219Reader()
    raise ValueError(f"Unknown BATTERY_BACKEND: {backend}")


def _poll_loop() -> None:
    global _cached_percent, _cached_voltage_mv

    while True:
        try:
            if _reader is None:
                break
            voltage_mv = _reader.read_mv()
            percent = _voltage_to_percent(voltage_mv)
            with _lock:
                _cached_voltage_mv = voltage_mv
                _cached_percent = percent
        except Exception as exc:
            log.debug("Battery read failed: %s", exc)
            with _lock:
                _cached_percent = None
                _cached_voltage_mv = None
        time.sleep(0.5)


def init() -> None:
    global _reader

    try:
        _reader = _make_reader()
    except Exception as exc:
        log.warning("Battery monitor disabled: %s", exc)
        _reader = None
        return

    if _reader is None:
        log.info("Battery monitor disabled (BATTERY_BACKEND=none)")
        return

    thread = threading.Thread(target=_poll_loop, name="battery_mon", daemon=True)
    thread.start()
    log.info("Battery monitor started (%s)", config.BATTERY_BACKEND)


def get_percent() -> int | None:
    with _lock:
        return _cached_percent


def get_voltage_mv() -> int | None:
    with _lock:
        return _cached_voltage_mv


def is_available() -> bool:
    with _lock:
        return _cached_percent is not None
