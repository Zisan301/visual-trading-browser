from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


@dataclass
class SignalHistoryMemory:
    signals: list[dict[str, Any]] = field(default_factory=list)
    seen_prediction_ids: set[str] = field(default_factory=set)


class SignalHistoryTracker:
    machine = "M2_8_SIGNAL_HISTORY_TRACKER"

    def __init__(self, max_items: int = 50) -> None:
        self.max_items = max_items
        self.memory = SignalHistoryMemory()

    def update(
        self,
        sequence: int,
        prediction_lock: dict[str, Any] | None,
    ) -> dict[str, Any]:
        prediction_lock = prediction_lock or {}
        signal = prediction_lock.get("signal")

        added = False

        if signal:
            prediction_id = str(signal.get("prediction_id", ""))

            if prediction_id and prediction_id not in self.memory.seen_prediction_ids:
                record = {
                    "history_id": f"HIST_{len(self.memory.signals) + 1:06d}",
                    "sequence": int(sequence),
                    "prediction_id": prediction_id,
                    "candle_id": signal.get("candle_id"),
                    "decision": signal.get("decision"),
                    "confidence": signal.get("confidence"),
                    "strategy_score": signal.get("strategy_score"),
                    "locked_at_second": signal.get("locked_at_second"),
                    "locked_at_sequence": signal.get("locked_at_sequence"),
                    "result": "PENDING",
                    "is_correct": None,
                    "prediction_only": True,
                    "auto_trade": False,
                }

                self.memory.signals.append(record)
                self.memory.seen_prediction_ids.add(prediction_id)
                added = True

                if len(self.memory.signals) > self.max_items:
                    removed = self.memory.signals.pop(0)
                    old_id = str(removed.get("prediction_id", ""))
                    if old_id:
                        self.memory.seen_prediction_ids.discard(old_id)

        recent = list(reversed(self.memory.signals[-10:]))
        last = recent[0] if recent else None

        return {
            "machine": self.machine,
            "total_locked_signals": len(self.memory.signals),
            "added_this_frame": added,
            "last_signal": last,
            "recent_signals": recent,
            "accuracy": {
                "status": "PLACEHOLDER",
                "resolved": 0,
                "correct": 0,
                "accuracy_percent": None,
                "note": "Future phase will compare locked prediction with candle outcome.",
            },
            "prediction_only": True,
            "auto_trade": False,
        }
