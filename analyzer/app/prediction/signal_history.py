from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from analyzer.app.prediction.candle_outcome_resolver import CandleOutcomeResolver


@dataclass
class SignalHistoryMemory:
    signals: list[dict[str, Any]] = field(default_factory=list)
    seen_prediction_ids: set[str] = field(default_factory=set)
    candle_snapshots: dict[str, dict[str, Any]] = field(default_factory=dict)


class SignalHistoryTracker:
    machine = "M3_0_STABLE_SIGNAL_PANEL"

    def __init__(self, max_items: int = 50) -> None:
        self.max_items = max_items
        self.memory = SignalHistoryMemory()
        self.resolver = CandleOutcomeResolver()

    def update(
        self,
        sequence: int,
        prediction_lock: dict[str, Any] | None,
        tracking: dict[str, Any] | None = None,
        current_candle: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        prediction_lock = prediction_lock or {}
        tracking = tracking or {}

        self._remember_current_candle(
            tracking=tracking,
            current_candle=current_candle,
        )

        signal = prediction_lock.get("signal")
        added = self._add_signal(sequence=sequence, signal=signal)

        resolved_this_frame = []
        if tracking.get("rollover_detected") and tracking.get("last_closed_candle_id"):
            resolved_this_frame = self._resolve_closed_candle(
                sequence=sequence,
                closed_candle_id=str(tracking["last_closed_candle_id"]),
            )

        recent = list(reversed(self.memory.signals[-10:]))
        last = recent[0] if recent else None

        panel_summary = self._panel_summary()
        accuracy = self._accuracy(panel_summary)

        return {
            "machine": self.machine,
            "outcome_resolver_machine": self.resolver.machine,
            "total_locked_signals": len(self.memory.signals),
            "added_this_frame": added,
            "resolved_this_frame": resolved_this_frame,
            "last_signal": last,
            "recent_signals": recent,
            "accuracy": accuracy,
            "panel_summary": panel_summary,
            "prediction_only": True,
            "auto_trade": False,
        }

    def _remember_current_candle(
        self,
        tracking: dict[str, Any],
        current_candle: dict[str, Any] | None,
    ) -> None:
        if not current_candle:
            return

        candle_id = current_candle.get("candle_id") or tracking.get("running_candle_id")

        if not candle_id:
            return

        snapshot = dict(current_candle)
        snapshot["snapshot_source"] = self.machine
        snapshot["running_candle_id"] = str(candle_id)

        self.memory.candle_snapshots[str(candle_id)] = snapshot

    def _add_signal(self, sequence: int, signal: dict[str, Any] | None) -> bool:
        if not signal:
            return False

        prediction_id = str(signal.get("prediction_id", ""))

        if not prediction_id or prediction_id in self.memory.seen_prediction_ids:
            return False

        strategy_score = signal.get("strategy_score") or {}

        record = {
            "history_id": f"HIST_{len(self.memory.signals) + 1:06d}",
            "sequence": int(sequence),
            "prediction_id": prediction_id,
            "candle_id": signal.get("candle_id"),
            "decision": signal.get("decision"),
            "confidence": signal.get("confidence"),
            "strategy_score": strategy_score,
            "locked_at_second": signal.get("locked_at_second"),
            "locked_at_sequence": signal.get("locked_at_sequence"),
            "result": "PENDING",
            "is_correct": None,
            "closed_direction": None,
            "resolved_at_sequence": None,
            "outcome_reason": None,
            "prediction_only": True,
            "auto_trade": False,
        }

        self.memory.signals.append(record)
        self.memory.seen_prediction_ids.add(prediction_id)

        if len(self.memory.signals) > self.max_items:
            removed = self.memory.signals.pop(0)
            old_id = str(removed.get("prediction_id", ""))
            if old_id:
                self.memory.seen_prediction_ids.discard(old_id)

        return True

    def _resolve_closed_candle(
        self,
        sequence: int,
        closed_candle_id: str,
    ) -> list[dict[str, Any]]:
        snapshot = self.memory.candle_snapshots.get(closed_candle_id)
        resolved = []

        for record in self.memory.signals:
            if record.get("candle_id") != closed_candle_id:
                continue

            if record.get("result") != "PENDING":
                continue

            outcome = self.resolver.resolve(
                signal_record=record,
                closed_candle_snapshot=snapshot,
                sequence=sequence,
            )

            record["result"] = outcome["result"]
            record["is_correct"] = outcome["is_correct"]
            record["closed_direction"] = outcome["closed_direction"]
            record["resolved_at_sequence"] = outcome["resolved_at_sequence"]
            record["outcome_reason"] = outcome["reason"]
            record["outcome"] = outcome

            resolved.append(record)

        return resolved

    def _panel_summary(self) -> dict[str, Any]:
        total = len(self.memory.signals)

        pending = [
            item for item in self.memory.signals
            if item.get("result") == "PENDING"
        ]

        resolved = [
            item for item in self.memory.signals
            if item.get("result") not in (None, "PENDING")
        ]

        wins = [
            item for item in self.memory.signals
            if item.get("result") == "WIN"
        ]

        losses = [
            item for item in self.memory.signals
            if item.get("result") == "LOSS"
        ]

        draws = [
            item for item in self.memory.signals
            if item.get("result") == "DRAW"
        ]

        skipped = [
            item for item in self.memory.signals
            if item.get("result") == "SKIPPED"
        ]

        scored_resolved = [
            item for item in resolved
            if item.get("is_correct") is not None
        ]

        correct = [
            item for item in scored_resolved
            if item.get("is_correct") is True
        ]

        accuracy_percent = None
        if scored_resolved:
            accuracy_percent = round((len(correct) / len(scored_resolved)) * 100, 2)

        last_locked = self.memory.signals[-1] if self.memory.signals else None
        last_resolved = resolved[-1] if resolved else None
        last_pending = pending[-1] if pending else None

        return {
            "machine": "M3_0_STABLE_SIGNAL_PANEL",
            "total": total,
            "pending": len(pending),
            "resolved": len(resolved),
            "wins": len(wins),
            "losses": len(losses),
            "draws": len(draws),
            "skipped": len(skipped),
            "correct": len(correct),
            "accuracy_percent": accuracy_percent,
            "last_locked_signal": last_locked,
            "last_resolved_signal": last_resolved,
            "last_pending_signal": last_pending,
            "prediction_only": True,
            "auto_trade": False,
        }

    def _accuracy(self, panel: dict[str, Any]) -> dict[str, Any]:
        return {
            "status": "READY" if panel["resolved"] else "WAITING_FOR_CLOSED_CANDLE",
            "resolved": panel["resolved"],
            "correct": panel["correct"],
            "wins": panel["wins"],
            "losses": panel["losses"],
            "draws": panel["draws"],
            "skipped": panel["skipped"],
            "pending": panel["pending"],
            "accuracy_percent": panel["accuracy_percent"],
            "note": "Prediction-only accuracy based on tracked candle rollover snapshots.",
        }
