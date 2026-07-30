from __future__ import annotations

from dataclasses import dataclass
from statistics import median

from analyzer.app.schemas import AnalysisResponse, VisualCandle


@dataclass
class TrackerState:
    candle_number: int = 1
    current_id: str = "LIVE_CANDLE_000001"
    current_started_sequence: int | None = None
    last_sequence: int | None = None
    previous_x_center: float | None = None
    previous_candle_count: int = 0
    frames_in_current: int = 0
    last_rollover_sequence: int | None = None
    total_rollovers: int = 0
    last_closed_candle_id: str | None = None


class LiveCandleTracker:
    """
    M2.4 live candle tracker.

    This does not predict trades.
    It only keeps a stable ID for the rightmost running candle
    and detects possible candle rollover.
    """

    def __init__(self) -> None:
        self.state = TrackerState()

    def update(self, response: AnalysisResponse) -> AnalysisResponse:
        sequence = int(response.sequence)
        candles = list(response.candles)
        current = response.current_candle

        if current is None or not candles:
            tracking = self._tracking_payload(
                sequence=sequence,
                tracker_ready=False,
                rollover_detected=False,
                current_x_center=None,
                estimated_spacing_px=None,
                warnings=["No current candle available for tracking"],
            )

            self.state.last_sequence = sequence
            return response.model_copy(update={"tracking": tracking})

        estimated_spacing = self._estimate_spacing(candles)
        rollover_detected = self._detect_rollover(
            current=current,
            candle_count=len(candles),
            estimated_spacing=estimated_spacing,
        )

        if self.state.current_started_sequence is None:
            self.state.current_started_sequence = sequence
            self.state.frames_in_current = 1
        elif rollover_detected:
            self.state.last_closed_candle_id = self.state.current_id
            self.state.total_rollovers += 1
            self.state.candle_number += 1
            self.state.current_id = f"LIVE_CANDLE_{self.state.candle_number:06d}"
            self.state.current_started_sequence = sequence
            self.state.last_rollover_sequence = sequence
            self.state.frames_in_current = 1
        else:
            self.state.frames_in_current += 1

        stable_current = current.model_copy(
            update={
                "candle_id": self.state.current_id,
                "status": "RUNNING",
            }
        )

        updated_candles: list[VisualCandle] = []

        for candle in candles:
            if candle.index == current.index:
                updated_candles.append(stable_current)
            else:
                updated_candles.append(
                    candle.model_copy(
                        update={
                            "candle_id": f"{self.state.current_id}_REL_{candle.index}",
                            "status": "CLOSED",
                        }
                    )
                )

        tracking = self._tracking_payload(
            sequence=sequence,
            tracker_ready=True,
            rollover_detected=rollover_detected,
            current_x_center=float(current.x_center),
            estimated_spacing_px=estimated_spacing,
            warnings=[],
        )

        self.state.previous_x_center = float(current.x_center)
        self.state.previous_candle_count = len(candles)
        self.state.last_sequence = sequence

        return response.model_copy(
            update={
                "candles": updated_candles,
                "current_candle": stable_current,
                "tracking": tracking,
            }
        )

    def _estimate_spacing(self, candles: list[VisualCandle]) -> float | None:
        if len(candles) < 3:
            return None

        x_values = sorted(float(candle.x_center) for candle in candles)
        gaps = [
            x_values[index + 1] - x_values[index]
            for index in range(len(x_values) - 1)
        ]

        useful_gaps = [gap for gap in gaps if 3.0 <= gap <= 120.0]

        if not useful_gaps:
            return None

        return float(median(useful_gaps))

    def _detect_rollover(
        self,
        current: VisualCandle,
        candle_count: int,
        estimated_spacing: float | None,
    ) -> bool:
        if self.state.previous_x_center is None:
            return False

        current_x = float(current.x_center)
        previous_x = float(self.state.previous_x_center)

        if estimated_spacing is None:
            min_move = 10.0
        else:
            min_move = max(5.0, estimated_spacing * 0.45)

        moved_right_enough = current_x - previous_x >= min_move

        candle_count_grew = (
            self.state.previous_candle_count > 0
            and candle_count > self.state.previous_candle_count
        )

        return bool(moved_right_enough or (candle_count_grew and current_x > previous_x))

    def _tracking_payload(
        self,
        sequence: int,
        tracker_ready: bool,
        rollover_detected: bool,
        current_x_center: float | None,
        estimated_spacing_px: float | None,
        warnings: list[str],
    ) -> dict:
        return {
            "tracker_ready": tracker_ready,
            "running_candle_id": self.state.current_id,
            "current_started_sequence": self.state.current_started_sequence,
            "frames_in_current": self.state.frames_in_current,
            "rollover_detected": rollover_detected,
            "last_rollover_sequence": self.state.last_rollover_sequence,
            "total_rollovers": self.state.total_rollovers,
            "last_closed_candle_id": self.state.last_closed_candle_id,
            "current_x_center": current_x_center,
            "previous_x_center": self.state.previous_x_center,
            "estimated_spacing_px": None
            if estimated_spacing_px is None
            else round(float(estimated_spacing_px), 2),
            "sequence": sequence,
            "warnings": warnings,
        }
