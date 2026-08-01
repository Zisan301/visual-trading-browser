from __future__ import annotations

from dataclasses import dataclass
from typing import Any


@dataclass
class TimingMachineMemory:
    active_candle_id: str | None = None
    cycle_number: int = 0
    locked_candle_id: str | None = None
    locked_sequence: int | None = None
    locked_cycle_number: int | None = None


class TimingStateMachine:
    machine = "M2_6_TIMING_STATE_MACHINE"

    def __init__(self) -> None:
        self.memory = TimingMachineMemory()

    def update(
        self,
        sequence: int,
        candle_second: int | None,
        candle_remaining: int | None,
        tracking: dict[str, Any] | None,
    ) -> dict[str, Any]:
        tracking = tracking or {}

        second = self._normalize_second(candle_second)
        remaining = self._normalize_remaining(candle_remaining, second)

        active_candle_id = tracking.get("running_candle_id")
        active_candle_id = str(active_candle_id) if active_candle_id else None
        tracker_ready = bool(tracking.get("tracker_ready", False))

        if active_candle_id != self.memory.active_candle_id:
            self.memory.active_candle_id = active_candle_id
            self.memory.locked_candle_id = None
            self.memory.locked_sequence = None
            self.memory.locked_cycle_number = None
            if active_candle_id is not None:
                self.memory.cycle_number = int(tracking.get("total_rollovers", 0)) + 1

        lock_window_open = second is not None and second >= 55
        already_locked = active_candle_id is not None and self.memory.locked_candle_id == active_candle_id
        lock_ready = bool(lock_window_open and tracker_ready and active_candle_id and not already_locked)

        locked_this_candle = False
        if lock_ready:
            self.memory.locked_candle_id = active_candle_id
            self.memory.locked_sequence = int(sequence)
            self.memory.locked_cycle_number = self.memory.cycle_number
            locked_this_candle = True
            already_locked = True

        state = self._state(second, already_locked)

        return {
            "machine": self.machine,
            "state": state,
            "phase": state,
            "cycle_number": self.memory.cycle_number,
            "sequence": int(sequence),
            "active_candle_id": active_candle_id,
            "candle_second": second,
            "candle_remaining": remaining,
            "lock_window_open": lock_window_open,
            "lock_ready": lock_ready,
            "locked_this_candle": locked_this_candle,
            "locked_candle_id": self.memory.locked_candle_id,
            "locked_sequence": self.memory.locked_sequence,
            "locked_cycle_number": self.memory.locked_cycle_number,
            "tracker_ready": tracker_ready,
            "prediction_only": True,
            "auto_trade": False,
            "no_signal_reason": "Strategy engine not implemented yet",
        }

    def _normalize_second(self, value: int | None) -> int | None:
        if value is None:
            return None
        try:
            return int(value) % 60
        except Exception:
            return None

    def _normalize_remaining(self, remaining: int | None, second: int | None) -> int | None:
        if remaining is not None:
            try:
                return max(0, min(60, int(remaining)))
            except Exception:
                pass
        if second is None:
            return None
        return 60 - int(second)

    def _state(self, second: int | None, already_locked: bool) -> str:
        if second is None:
            return "WAITING"
        if already_locked:
            return "LOCKED"
        if second >= 55:
            return "LOCK_WINDOW"
        if second >= 40:
            return "FORMING_SCAN"
        return "OBSERVING"



