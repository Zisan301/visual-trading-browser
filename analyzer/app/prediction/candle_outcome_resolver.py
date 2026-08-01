from __future__ import annotations

from typing import Any


class CandleOutcomeResolver:
    """
    M2.9 candle outcome resolver.

    Resolves prediction-only locked signals after the tracked candle rolls over.
    It does not place trades, click platform buttons, or call private platform APIs.
    """

    machine = "M2_9_CANDLE_OUTCOME_RESOLVER"

    def resolve(
        self,
        signal_record: dict[str, Any],
        closed_candle_snapshot: dict[str, Any] | None,
        sequence: int,
    ) -> dict[str, Any]:
        decision = str(signal_record.get("decision", "NO_SIGNAL")).upper()
        snapshot = closed_candle_snapshot or {}
        closed_direction = str(snapshot.get("direction", "UNKNOWN")).upper()

        if decision == "NO_SIGNAL":
            result = "SKIPPED"
            is_correct = None
            reason = "No signal was locked, so outcome is skipped."
        elif closed_direction in ("DRAW", "UNKNOWN"):
            result = "DRAW"
            is_correct = None
            reason = f"Closed candle direction is {closed_direction}."
        elif decision == "CALL_WATCH":
            is_correct = closed_direction == "GREEN"
            result = "WIN" if is_correct else "LOSS"
            reason = f"CALL_WATCH resolved against closed candle direction {closed_direction}."
        elif decision == "PUT_WATCH":
            is_correct = closed_direction == "RED"
            result = "WIN" if is_correct else "LOSS"
            reason = f"PUT_WATCH resolved against closed candle direction {closed_direction}."
        else:
            result = "SKIPPED"
            is_correct = None
            reason = f"Unsupported decision {decision}."

        return {
            "machine": self.machine,
            "result": result,
            "is_correct": is_correct,
            "closed_direction": closed_direction,
            "resolved_at_sequence": int(sequence),
            "reason": reason,
            "closed_candle_snapshot": snapshot,
            "prediction_only": True,
            "auto_trade": False,
        }
