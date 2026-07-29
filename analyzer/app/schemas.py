from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel, Field


Direction = Literal["GREEN", "RED", "DRAW", "UNKNOWN"]
CandleStatus = Literal["HISTORICAL", "CLOSED", "RUNNING", "UNKNOWN"]


class FrameMetadata(BaseModel):
    session_id: str = "LOCAL_SESSION"
    frame_sequence: int = 0
    platform: str = "unknown"
    asset: str = "unknown"
    timeframe: str = "1m"
    captured_at: str | None = None
    phase: str = "M2_DETECTOR_ONLY"


class VisualCandle(BaseModel):
    candle_id: str
    index: int
    x_center: float
    open_y: float
    high_y: float
    low_y: float
    close_y: float
    direction: Direction
    status: CandleStatus = "UNKNOWN"
    body_px: float
    upper_wick_px: float
    lower_wick_px: float
    range_px: float
    body_ratio: float
    upper_wick_ratio: float
    lower_wick_ratio: float
    close_location: float
    detection_confidence: float = Field(ge=0.0, le=1.0)


class DetectorStatus(BaseModel):
    chart_found: bool
    candle_count: int
    confidence: float = Field(ge=0.0, le=1.0)
    warnings: list[str] = Field(default_factory=list)


class AnalysisResponse(BaseModel):
    type: str = "ANALYSIS_RESULT"
    sequence: int
    detector: DetectorStatus
    candles: list[VisualCandle]
    current_candle: VisualCandle | None = None
    timing: dict[str, Any] = Field(default_factory=dict)
    market: dict[str, Any] = Field(default_factory=dict)
    signals: list[dict[str, Any]] = Field(default_factory=list)
