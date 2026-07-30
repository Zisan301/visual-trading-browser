from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable

import cv2
import numpy as np

from analyzer.app.schemas import AnalysisResponse, DetectorStatus, VisualCandle


@dataclass(frozen=True)
class CandleDetectorConfig:
    min_candle_height_px: int = 8
    min_candle_width_px: int = 2
    min_colored_pixels_per_column: int = 2
    max_gap_between_columns_px: int = 1
    merge_nearby_groups_px: int = 0


class VisualCandleDetector:
    """
    M2 visual candle detector.

    This is the first OpenCV detector, not the final trading logic.
    It separates common green/red candle pixels, groups them by x-position,
    and converts each visual group into a VisualCandle object.
    """

    def __init__(self, config: CandleDetectorConfig | None = None) -> None:
        self.config = config or CandleDetectorConfig()

    def analyze_image(self, image_bgr: np.ndarray, sequence: int = 0) -> AnalysisResponse:
        height, width = image_bgr.shape[:2]
        warnings: list[str] = []

        bullish_mask, bearish_mask = self._build_color_masks(image_bgr)
        combined_mask = cv2.bitwise_or(bullish_mask, bearish_mask)
        combined_mask = self._clean_mask(combined_mask)

        groups = self._find_x_groups(combined_mask)
        candles: list[VisualCandle] = []

        for raw_index, group in enumerate(groups):
            candle = self._group_to_candle(
                candle_index=raw_index,
                x_group=group,
                bullish_mask=bullish_mask,
                bearish_mask=bearish_mask,
                combined_mask=combined_mask,
            )
            if candle is not None:
                candles.append(candle)

        candles.sort(key=lambda item: item.x_center)
        candles = self._reindex_candles(candles)

        if not candles:
            warnings.append("No red/green candle-like shapes found")

        confidence = self._overall_confidence(candles, width=width, height=height)
        detector = DetectorStatus(
            chart_found=len(candles) > 0,
            candle_count=len(candles),
            confidence=confidence,
            warnings=warnings,
        )

        current_candle = candles[-1] if candles else None

        return AnalysisResponse(
            sequence=sequence,
            detector=detector,
            candles=candles,
            current_candle=current_candle,
            timing={"phase": "M2_DETECTOR_ONLY"},
            market={"mode": "NOT_ANALYZED_IN_M2"},
            signals=[],
        )

    def _build_color_masks(self, image_bgr: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        hsv = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2HSV)

        # Common candle greens in TradingView/Quotex/Pocket Option style themes.
        bullish_1 = cv2.inRange(hsv, np.array([35, 35, 35]), np.array([95, 255, 255]))

        # Red wraps around HSV hue boundary, so use two ranges.
        bearish_low = cv2.inRange(hsv, np.array([0, 35, 35]), np.array([12, 255, 255]))
        bearish_high = cv2.inRange(hsv, np.array([165, 35, 35]), np.array([179, 255, 255]))
        bearish = cv2.bitwise_or(bearish_low, bearish_high)

        return bullish_1, bearish

    def _clean_mask(self, mask: np.ndarray) -> np.ndarray:
        kernel_small = np.ones((2, 2), dtype=np.uint8)
        kernel_tall = np.ones((3, 1), dtype=np.uint8)
        cleaned = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel_small, iterations=1)
        cleaned = cv2.morphologyEx(cleaned, cv2.MORPH_CLOSE, kernel_tall, iterations=1)
        return cleaned

    def _find_x_groups(self, mask: np.ndarray) -> list[tuple[int, int]]:
        pixel_counts = np.count_nonzero(mask > 0, axis=0)
        active_columns = np.where(pixel_counts >= self.config.min_colored_pixels_per_column)[0]

        if active_columns.size == 0:
            return []

        groups: list[tuple[int, int]] = []
        start = int(active_columns[0])
        previous = int(active_columns[0])

        for value in active_columns[1:]:
            current = int(value)
            if current - previous > self.config.max_gap_between_columns_px:
                groups.append((start, previous))
                start = current
            previous = current

        groups.append((start, previous))
        return self._merge_nearby_groups(groups)

    def _merge_nearby_groups(self, groups: Iterable[tuple[int, int]]) -> list[tuple[int, int]]:
        merged: list[tuple[int, int]] = []

        for start, end in groups:
            if not merged:
                merged.append((start, end))
                continue

            prev_start, prev_end = merged[-1]
            if start - prev_end <= self.config.merge_nearby_groups_px:
                merged[-1] = (prev_start, max(prev_end, end))
            else:
                merged.append((start, end))

        return merged

    def _group_to_candle(
        self,
        candle_index: int,
        x_group: tuple[int, int],
        bullish_mask: np.ndarray,
        bearish_mask: np.ndarray,
        combined_mask: np.ndarray,
    ) -> VisualCandle | None:
        x1, x2 = x_group
        group_width = x2 - x1 + 1

        if group_width < self.config.min_candle_width_px:
            return None

        group_mask = combined_mask[:, x1 : x2 + 1]
        y_values, x_values = np.where(group_mask > 0)

        if y_values.size == 0:
            return None

        high_y = float(np.min(y_values))
        low_y = float(np.max(y_values))
        range_px = max(low_y - high_y, 1.0)

        if range_px < self.config.min_candle_height_px:
            return None

        image_height = combined_mask.shape[0]
        if range_px > image_height * 0.72 and group_width <= 8:
            return None

        bullish_pixels = int(np.count_nonzero(bullish_mask[:, x1 : x2 + 1] > 0))
        bearish_pixels = int(np.count_nonzero(bearish_mask[:, x1 : x2 + 1] > 0))

        if bullish_pixels == bearish_pixels:
            direction = "UNKNOWN"
        elif bullish_pixels > bearish_pixels:
            direction = "GREEN"
        else:
            direction = "RED"

        dominant_mask = bullish_mask if direction == "GREEN" else bearish_mask
        dominant_group = dominant_mask[:, x1 : x2 + 1]
        dominant_y, dominant_x = np.where(dominant_group > 0)

        if dominant_y.size == 0:
            return None

        body_top = float(np.percentile(dominant_y, 20))
        body_bottom = float(np.percentile(dominant_y, 80))
        body_px = max(body_bottom - body_top, 1.0)

        if direction == "GREEN":
            open_y = body_bottom
            close_y = body_top
        elif direction == "RED":
            open_y = body_top
            close_y = body_bottom
        else:
            open_y = body_bottom
            close_y = body_bottom

        upper_wick_px = max(min(open_y, close_y) - high_y, 0.0)
        lower_wick_px = max(low_y - max(open_y, close_y), 0.0)
        body_ratio = float(body_px / max(range_px, 1.0))
        upper_wick_ratio = float(upper_wick_px / max(body_px, 1.0))
        lower_wick_ratio = float(lower_wick_px / max(body_px, 1.0))
        close_location = float((close_y - high_y) / max(range_px, 1.0))

        dominant_total = max(bullish_pixels + bearish_pixels, 1)
        color_purity = max(bullish_pixels, bearish_pixels) / dominant_total
        height_score = min(range_px / 25.0, 1.0)
        width_score = min(group_width / 8.0, 1.0)
        detection_confidence = float(max(0.0, min(1.0, 0.5 * color_purity + 0.25 * height_score + 0.25 * width_score)))

        return VisualCandle(
            candle_id=f"M2_CANDLE_RAW_{candle_index:04d}",
            index=candle_index,
            x_center=float((x1 + x2) / 2.0),
            open_y=float(open_y),
            high_y=float(high_y),
            low_y=float(low_y),
            close_y=float(close_y),
            direction=direction,
            status="UNKNOWN",
            body_px=float(body_px),
            upper_wick_px=float(upper_wick_px),
            lower_wick_px=float(lower_wick_px),
            range_px=float(range_px),
            body_ratio=body_ratio,
            upper_wick_ratio=upper_wick_ratio,
            lower_wick_ratio=lower_wick_ratio,
            close_location=close_location,
            detection_confidence=detection_confidence,
        )

    def _reindex_candles(self, candles: list[VisualCandle]) -> list[VisualCandle]:
        if not candles:
            return []

        output: list[VisualCandle] = []
        last_index = len(candles) - 1

        for position, candle in enumerate(candles):
            relative_index = position - last_index
            status = "RUNNING" if position == last_index else "CLOSED"
            output.append(
                candle.model_copy(
                    update={
                        "candle_id": f"M2_CANDLE_{relative_index}",
                        "index": relative_index,
                        "status": status,
                    }
                )
            )

        return output

    def _overall_confidence(self, candles: list[VisualCandle], width: int, height: int) -> float:
        if not candles:
            return 0.0

        avg_candle_conf = sum(item.detection_confidence for item in candles) / len(candles)
        count_score = min(len(candles) / 30.0, 1.0)
        return float(max(0.0, min(1.0, 0.7 * avg_candle_conf + 0.3 * count_score)))


