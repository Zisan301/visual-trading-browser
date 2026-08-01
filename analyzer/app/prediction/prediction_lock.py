from __future__ import annotations

from dataclasses import dataclass
from typing import Any


@dataclass
class PredictionLockMemory:
    active_candle_id: str | None = None
    locked_prediction: dict[str, Any] | None = None


class PredictionLockManager:
    machine = "M2_6_PREDICTION_LOCK_WINDOW"

    def __init__(self) -> None:
        self.memory = PredictionLockMemory()

    def update(
        self,
        sequence: int,
        timing: dict[str, Any] | None,
        current_candle: dict[str, Any] | None,
        tracking: dict[str, Any] | None,
    ) -> dict[str, Any]:
        timing = timing or {}
        tracking = tracking or {}

        active_candle_id = timing.get("active_candle_id") or tracking.get("running_candle_id")
        active_candle_id = str(active_candle_id) if active_candle_id else None

        if active_candle_id != self.memory.active_candle_id:
            self.memory.active_candle_id = active_candle_id
            self.memory.locked_prediction = None

        lock_window_open = bool(timing.get("lock_window_open", False))
        locked_this_frame = bool(timing.get("locked_this_candle", False))

        signal = None

        if locked_this_frame and self.memory.locked_prediction is None:
            self.memory.locked_prediction = self._build_locked_prediction(
                sequence=sequence,
                timing=timing,
                current_candle=current_candle,
                active_candle_id=active_candle_id,
            )
            signal = self.memory.locked_prediction

        if self.memory.locked_prediction:
            status = "LOCKED"
        elif lock_window_open:
            status = "LOCK_WINDOW_OPEN"
        else:
            status = "WAITING_FOR_LOCK_WINDOW"

        return {
            "machine": self.machine,
            "status": status,
            "active_candle_id": active_candle_id,
            "lock_window_open": lock_window_open,
            "locked_this_frame": locked_this_frame,
            "locked_prediction": self.memory.locked_prediction,
            "signal": signal,
            "prediction_only": True,
            "auto_trade": False,
            "note": "Prediction-only visual lock. No automatic trade action.",
        }

    def _build_locked_prediction(
        self,
        sequence: int,
        timing: dict[str, Any],
        current_candle: dict[str, Any] | None,
        active_candle_id: str | None,
    ) -> dict[str, Any]:
        current_candle = current_candle or {}

        direction = str(current_candle.get("direction", "UNKNOWN")).upper()
        raw_confidence = current_candle.get("detection_confidence", 0.0)

        try:
            detector_confidence = float(raw_confidence)
        except Exception:
            detector_confidence = 0.0

        if direction == "GREEN":
            decision = "CALL_WATCH"
        elif direction == "RED":
            decision = "PUT_WATCH"
        else:
            decision = "NO_SIGNAL"

        confidence = round(max(0.0, min(1.0, detector_confidence * 0.60)), 4)

        return {
            "prediction_id": f"PRED_{active_candle_id or 'UNKNOWN'}_{int(sequence)}",
            "candle_id": active_candle_id,
            "locked_at_sequence": int(sequence),
            "locked_at_second": timing.get("candle_second"),
            "locked_cycle_number": timing.get("locked_cycle_number"),
            "decision": decision,
            "direction_basis": direction,
            "confidence": confidence,
            "is_locked": True,
            "prediction_only": True,
            "auto_trade": False,
            "source": self.machine,
            "rationale": "Locked once during 55-59s window using current visual candle direction placeholder.",
        }
