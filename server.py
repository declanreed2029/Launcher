#!/usr/bin/env python3
"""Launcher Pi — WiFi HUD web server with pan servo and battery status."""

from __future__ import annotations

import atexit
import logging
from pathlib import Path

from flask import Flask, jsonify, request, send_from_directory

import battery_monitor
import config
import pan_servo

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")
log = logging.getLogger("launcher")

BASE_DIR = Path(__file__).resolve().parent
STATIC_DIR = BASE_DIR / "static"
ASSETS_DIR = BASE_DIR / "assets"
INTRO_VIDEO_NAME = "Intro.mp4"


def _intro_video_path() -> Path | None:
    for directory in (ASSETS_DIR, STATIC_DIR):
        candidate = directory / INTRO_VIDEO_NAME
        if candidate.is_file():
            return candidate
    return None


def _intro_video_dir() -> Path:
    path = _intro_video_path()
    if path is not None:
        return path.parent
    return ASSETS_DIR

app = Flask(__name__, static_folder=str(STATIC_DIR), static_url_path="")

_pan_deg = 0
_tilt_deg = 90


def _clamp_pan_tilt() -> None:
    global _pan_deg, _tilt_deg

    _pan_deg = max(config.PAN_MIN_DEG, min(config.PAN_MAX_DEG, _pan_deg))
    _tilt_deg = max(config.TILT_MIN_DEG, min(config.TILT_MAX_DEG, _tilt_deg))


def _apply_move(move: str) -> None:
    global _pan_deg, _tilt_deg

    if move == "up":
        _tilt_deg -= config.MOVE_STEP_DEG
    elif move == "down":
        _tilt_deg += config.MOVE_STEP_DEG
    elif move == "left":
        _pan_deg -= config.MOVE_STEP_DEG
    elif move == "right":
        _pan_deg += config.MOVE_STEP_DEG
    elif move == "center":
        _pan_deg = 0
        _tilt_deg = 90
    else:
        return

    _clamp_pan_tilt()
    pan_servo.set_pan_deg(_pan_deg)


@app.get("/")
def index():
    return send_from_directory(STATIC_DIR, "index.html")


@app.get("/assets/<path:filename>")
def assets(filename: str):
    if filename == INTRO_VIDEO_NAME:
        intro_dir = _intro_video_dir()
        if (intro_dir / INTRO_VIDEO_NAME).is_file():
            return send_from_directory(intro_dir, INTRO_VIDEO_NAME)
    return send_from_directory(ASSETS_DIR, filename)


@app.get("/Intro.mp4")
def intro_video_legacy():
    intro_dir = _intro_video_dir()
    if not (intro_dir / INTRO_VIDEO_NAME).is_file():
        log.error("Intro video missing — put %s in %s or %s", INTRO_VIDEO_NAME, ASSETS_DIR, STATIC_DIR)
        return "Intro video not found", 404
    return send_from_directory(intro_dir, INTRO_VIDEO_NAME)


@app.get("/api/status")
def api_status():
    payload = {
        "pan_deg": _pan_deg,
        "tilt_deg": _tilt_deg,
    }

    if battery_monitor.is_available():
        payload["battery_percent"] = battery_monitor.get_percent()
        payload["battery_voltage_mv"] = battery_monitor.get_voltage_mv()
    else:
        payload["battery_percent"] = None
        payload["battery_voltage_mv"] = None

    return jsonify(payload)


@app.get("/cmd")
def cmd():
    move = request.args.get("move", "")
    log.info("Received command: %s", move)

    valid = {"up", "down", "left", "right", "center"}
    if move in valid:
        _apply_move(move)
        return "OK", 200

    return "ERR", 400


def _shutdown() -> None:
    pan_servo.cleanup()


def main() -> None:
    intro = _intro_video_path()
    if intro is None:
        log.warning(
            "Intro.mp4 not found — copy it to %s or %s",
            ASSETS_DIR / INTRO_VIDEO_NAME,
            STATIC_DIR / INTRO_VIDEO_NAME,
        )
    else:
        log.info("Intro video: %s", intro)

    battery_monitor.init()
    pan_servo.init()
    atexit.register(_shutdown)

    log.info("Launcher HUD on http://192.168.4.1:%d", config.WEB_PORT)
    app.run(host=config.WEB_HOST, port=config.WEB_PORT, threaded=True)


if __name__ == "__main__":
    main()
