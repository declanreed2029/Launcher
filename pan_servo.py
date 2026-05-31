"""Backward-compatible shim — use servos.py for pan + tilt."""

from servos import cleanup, init, set_pan_deg

__all__ = ["init", "set_pan_deg", "cleanup"]
