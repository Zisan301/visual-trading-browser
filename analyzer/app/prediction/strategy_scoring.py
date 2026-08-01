from __future__ import annotations

from typing import Any


class StrategyScoringEngine:
    """
    M2.7 placeholder visual strategy scorer.

    This is intentionally conservative and prediction-only.
    It does not place trades, click buttons, or call platform APIs.
    """

    machine = "M2_7_STRATEGY_SCORING_PLACEHOLDER"

    def score(self, current_candle: dict[str, Any] | None) -> dict[str, Any]:
        if not current_candle:
            return self._no_signal("No current candle available")

        direction = str(current_candle.get("direction", "UNKNOWN")).upper()

        detection_confidence = self._float(current_candle.get("detection_confidence"), 0.0)
        body_ratio = self._float(current_candle.get("body_ratio"), 0.0)
        upper_wick_ratio = self._float(current_candle.get("upper_wick_ratio"), 0.0)
        lower_wick_ratio = self._float(current_candle.get("lower_wick_ratio"), 0.0)
        close_location = self._float(current_candle.get("close_location"), 0.5)

        detection_confidence = self._clamp(detection_confidence, 0.0, 1.0)
        body_ratio = self._clamp(body_ratio, 0.0, 1.0)
        upper_wick_ratio = self._clamp(upper_wick_ratio, 0.0, 1.0)
        lower_wick_ratio = self._clamp(lower_wick_ratio, 0.0, 1.0)
        close_location = self._clamp(close_location, 0.0, 1.0)

        if direction == "GREEN":
            directional_score = (
                0.35
                + body_ratio * 0.30
                + close_location * 0.20
                + lower_wick_ratio * 0.10
                - upper_wick_ratio * 0.08
            )
            decision = "CALL_WATCH"
            reason = "Green candle with body/close-position support"
        elif direction == "RED":
            directional_score = (
                0.35
                + body_ratio * 0.30
                + (1.0 - close_location) * 0.20
                + upper_wick_ratio * 0.10
                - lower_wick_ratio * 0.08
            )
            decision = "PUT_WATCH"
            reason = "Red candle with body/close-position support"
        else:
            return self._no_signal("Current candle direction is unknown")

        raw_score = self._clamp(directional_score, 0.0, 1.0)
        confidence = self._clamp((raw_score * 0.70) + (detection_confidence * 0.30), 0.0, 1.0)

        minimum_confidence = 0.42
        weak_signal = confidence < minimum_confidence

        if weak_signal:
            decision = "NO_SIGNAL"
            reason = f"Weak visual setup below threshold {minimum_confidence:.2f}"

        return {
            "machine": self.machine,
            "decision": decision,
            "confidence": round(confidence, 4),
            "overall_score": round(raw_score, 4),
            "direction_basis": direction,
            "weak_signal": weak_signal,
            "minimum_confidence": minimum_confidence,
            "reason": reason,
            "components": {
                "detection_confidence": round(detection_confidence, 4),
                "body_ratio": round(body_ratio, 4),
                "upper_wick_ratio": round(upper_wick_ratio, 4),
                "lower_wick_ratio": round(lower_wick_ratio, 4),
                "close_location": round(close_location, 4),
            },
            "prediction_only": True,
            "auto_trade": False,
        }

    def _no_signal(self, reason: str) -> dict[str, Any]:
        return {
            "machine": self.machine,
            "decision": "NO_SIGNAL",
            "confidence": 0.0,
            "overall_score": 0.0,
            "direction_basis": "UNKNOWN",
            "weak_signal": True,
            "minimum_confidence": 0.42,
            "reason": reason,
            "components": {},
            "prediction_only": True,
            "auto_trade": False,
        }

    def _float(self, value: Any, default: float) -> float:
        try:
            return float(value)
        except Exception:
            return default

    def _clamp(self, value: float, low: float, high: float) -> float:
        return max(low, min(high, value))
