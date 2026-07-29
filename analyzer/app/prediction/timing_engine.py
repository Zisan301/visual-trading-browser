from __future__ import annotations


def get_phase_from_second(candle_second: int | float | None) -> str:
    """
    Minimal timing helper for M2.

    The user requested to fix final timing later, so this module only exposes
    the project phase names without locking real predictions yet.
    """
    if candle_second is None:
        return "WAITING"

    second = int(candle_second) % 60

    if second >= 55:
        return "LOCK_WINDOW"
    if second >= 40:
        return "FORMING_SCAN"
    return "OBSERVING"
