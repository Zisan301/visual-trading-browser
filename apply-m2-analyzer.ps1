
param(
  [string]$ProjectDir = "E:\VS Code\visual-trading-browser",
  [switch]$Install,
  [switch]$RunAnalyzer
)

$ErrorActionPreference = "Stop"

function Write-Info($Message) {
  Write-Host "[M2] $Message" -ForegroundColor Cyan
}

function Write-Ok($Message) {
  Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Warn($Message) {
  Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Ensure-Directory($PathValue) {
  if (-not (Test-Path $PathValue)) {
    New-Item -ItemType Directory -Force -Path $PathValue | Out-Null
  }
}

function Backup-ExistingFile($PathValue) {
  if (Test-Path $PathValue) {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupPath = "$PathValue.bak-$timestamp"
    Copy-Item -Path $PathValue -Destination $backupPath -Force
    Write-Warn "Backup created: $backupPath"
  }
}

function Write-ProjectFile([string]$RelativePath, [string]$Content) {
  $fullPath = Join-Path $ProjectDir $RelativePath
  $parent = Split-Path $fullPath -Parent
  Ensure-Directory $parent
  Backup-ExistingFile $fullPath
  Set-Content -Path $fullPath -Value $Content -Encoding UTF8
  Write-Ok "Wrote $RelativePath"
}

if (-not (Test-Path $ProjectDir)) {
  throw "Project directory not found: $ProjectDir"
}

Set-Location $ProjectDir
Write-Info "Working directory: $ProjectDir"

# Keep this aligned with the project directory requested in the thesis plan:
# visual-trading-browser/analyzer/app/...
Ensure-Directory (Join-Path $ProjectDir "analyzer")
Ensure-Directory (Join-Path $ProjectDir "analyzer\app")
Ensure-Directory (Join-Path $ProjectDir "analyzer\app\capture")
Ensure-Directory (Join-Path $ProjectDir "analyzer\app\vision")
Ensure-Directory (Join-Path $ProjectDir "analyzer\app\prediction")
Ensure-Directory (Join-Path $ProjectDir "analyzer\tools")
Ensure-Directory (Join-Path $ProjectDir "scripts")
Ensure-Directory (Join-Path $ProjectDir "data")

Write-ProjectFile "analyzer\__init__.py" @'
"""Analyzer package for Visual Trading Browser."""
'@

Write-ProjectFile "analyzer\requirements.txt" @'
fastapi>=0.111,<1.0
uvicorn[standard]>=0.30,<1.0
opencv-python>=4.10,<5.0
numpy>=1.26,<3.0
pydantic>=2.7,<3.0
python-multipart>=0.0.9,<1.0
'@

Write-ProjectFile "analyzer\app\__init__.py" @'
"""FastAPI/OpenCV analyzer application."""
'@

Write-ProjectFile "analyzer\app\schemas.py" @'
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
'@

Write-ProjectFile "analyzer\app\capture\__init__.py" @'
"""Frame receiving and validation helpers."""
'@

Write-ProjectFile "analyzer\app\capture\frame_receiver.py" @'
from __future__ import annotations

import base64
import re

import cv2
import numpy as np


_DATA_URL_RE = re.compile(r"^data:image/[a-zA-Z0-9.+-]+;base64,")


class FrameDecodeError(ValueError):
    pass


def decode_image_bytes(image_bytes: bytes) -> np.ndarray:
    if not image_bytes:
        raise FrameDecodeError("Empty image bytes received")

    arr = np.frombuffer(image_bytes, dtype=np.uint8)
    image = cv2.imdecode(arr, cv2.IMREAD_COLOR)

    if image is None:
        raise FrameDecodeError("Could not decode image. Send PNG or JPEG bytes.")

    return image


def decode_base64_image(data: str) -> np.ndarray:
    if not data:
        raise FrameDecodeError("Empty base64 image received")

    cleaned = _DATA_URL_RE.sub("", data.strip())

    try:
        raw = base64.b64decode(cleaned, validate=False)
    except Exception as exc:
        raise FrameDecodeError(f"Invalid base64 image: {exc}") from exc

    return decode_image_bytes(raw)
'@

Write-ProjectFile "analyzer\app\capture\frame_validator.py" @'
from __future__ import annotations

import numpy as np


class FrameValidationError(ValueError):
    pass


def validate_frame(image: np.ndarray, min_width: int = 240, min_height: int = 160) -> None:
    if image is None:
        raise FrameValidationError("Frame is None")

    if image.ndim != 3 or image.shape[2] != 3:
        raise FrameValidationError("Frame must be a 3-channel BGR image")

    height, width = image.shape[:2]

    if width < min_width or height < min_height:
        raise FrameValidationError(
            f"Frame too small: {width}x{height}. Minimum required: {min_width}x{min_height}."
        )
'@

Write-ProjectFile "analyzer\app\vision\__init__.py" @'
"""OpenCV based visual detectors."""
'@

Write-ProjectFile "analyzer\app\vision\candle_detector.py" @'
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
    max_gap_between_columns_px: int = 4
    merge_nearby_groups_px: int = 5


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
'@

Write-ProjectFile "analyzer\app\prediction\__init__.py" @'
"""Prediction related modules. M2 keeps this minimal; timing will be refined later."""
'@

Write-ProjectFile "analyzer\app\prediction\timing_engine.py" @'
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
'@

Write-ProjectFile "analyzer\app\main.py" @'
from __future__ import annotations

import json
from typing import Any

from fastapi import FastAPI, File, Form, HTTPException, UploadFile, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware

from analyzer.app.capture.frame_receiver import FrameDecodeError, decode_base64_image, decode_image_bytes
from analyzer.app.capture.frame_validator import FrameValidationError, validate_frame
from analyzer.app.schemas import FrameMetadata
from analyzer.app.vision.candle_detector import VisualCandleDetector

app = FastAPI(
    title="Visual Trading Browser Analyzer",
    version="0.2.0",
    description="M2 FastAPI + OpenCV visual candle detector. Prediction-only. No trading actions.",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://127.0.0.1", "http://localhost", "file://"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

_detector = VisualCandleDetector()


@app.get("/health")
def health() -> dict[str, Any]:
    return {
        "ok": True,
        "service": "visual-trading-browser-analyzer",
        "phase": "M2_FASTAPI_OPENCV_DETECTOR",
        "prediction_only": True,
        "auto_trade": False,
    }


@app.post("/analyze-frame")
async def analyze_frame(
    file: UploadFile = File(...),
    metadata_json: str | None = Form(default=None),
) -> dict[str, Any]:
    metadata = _parse_metadata(metadata_json)

    try:
        raw = await file.read()
        image = decode_image_bytes(raw)
        validate_frame(image)
        result = _detector.analyze_image(image, sequence=metadata.frame_sequence)
        return result.model_dump()
    except (FrameDecodeError, FrameValidationError) as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Analyzer failed: {exc}") from exc


@app.websocket("/ws/analyze")
async def websocket_analyze(websocket: WebSocket) -> None:
    await websocket.accept()
    sequence = 0

    try:
        while True:
            message = await websocket.receive()
            sequence += 1

            try:
                image, metadata = _decode_websocket_message(message, sequence)
                validate_frame(image)
                result = _detector.analyze_image(image, sequence=metadata.frame_sequence)
                await websocket.send_json(result.model_dump())
            except Exception as exc:
                await websocket.send_json(
                    {
                        "type": "ANALYSIS_ERROR",
                        "sequence": sequence,
                        "ok": False,
                        "error": str(exc),
                    }
                )
    except WebSocketDisconnect:
        return


def _parse_metadata(metadata_json: str | None) -> FrameMetadata:
    if not metadata_json:
        return FrameMetadata()

    try:
        data = json.loads(metadata_json)
        return FrameMetadata.model_validate(data)
    except Exception:
        return FrameMetadata()


def _decode_websocket_message(message: dict[str, Any], fallback_sequence: int) -> tuple[Any, FrameMetadata]:
    if "bytes" in message and message["bytes"]:
        metadata = FrameMetadata(frame_sequence=fallback_sequence)
        return decode_image_bytes(message["bytes"]), metadata

    if "text" in message and message["text"]:
        payload = json.loads(message["text"])
        metadata = FrameMetadata.model_validate(payload.get("metadata", {"frame_sequence": fallback_sequence}))
        image_base64 = payload.get("image") or payload.get("image_base64")

        if not image_base64:
            raise ValueError("Text WebSocket message must include image or image_base64")

        return decode_base64_image(image_base64), metadata

    raise ValueError("Unsupported WebSocket message. Send PNG/JPEG bytes or JSON with image_base64.")
'@

Write-ProjectFile "analyzer\tools\__init__.py" @'
"""Analyzer developer tools."""
'@

Write-ProjectFile "analyzer\tools\smoke_test.py" @'
from __future__ import annotations

from pathlib import Path

import cv2
import numpy as np

from analyzer.app.vision.candle_detector import VisualCandleDetector


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "data" / "m2-smoke-chart.png"


def draw_candle(img: np.ndarray, x: int, open_y: int, close_y: int, high_y: int, low_y: int) -> None:
    green = (0, 200, 0)
    red = (0, 0, 220)
    color = green if close_y < open_y else red
    body_top = min(open_y, close_y)
    body_bottom = max(open_y, close_y)

    cv2.line(img, (x, high_y), (x, low_y), color, 2)
    cv2.rectangle(img, (x - 4, body_top), (x + 4, body_bottom), color, -1)


def make_test_chart() -> np.ndarray:
    height, width = 360, 640
    img = np.full((height, width, 3), 18, dtype=np.uint8)

    for y in range(40, height - 20, 40):
        cv2.line(img, (20, y), (width - 20, y), (35, 35, 35), 1)

    rng = np.random.default_rng(7)
    base = 190

    for i, x in enumerate(range(50, 600, 22)):
        move = int(rng.integers(-28, 29))
        open_y = int(base)
        close_y = int(np.clip(base + move, 70, 290))
        high_y = int(max(35, min(open_y, close_y) - rng.integers(8, 35)))
        low_y = int(min(325, max(open_y, close_y) + rng.integers(8, 35)))
        draw_candle(img, x, open_y, close_y, high_y, low_y)
        base = int(np.clip(close_y + rng.integers(-10, 11), 90, 270))

    return img


def main() -> None:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    image = make_test_chart()
    cv2.imwrite(str(OUT), image)

    detector = VisualCandleDetector()
    result = detector.analyze_image(image, sequence=1)

    print("M2 smoke test image:", OUT)
    print("Detected candles:", result.detector.candle_count)
    print("Detector confidence:", round(result.detector.confidence, 3))

    if result.detector.candle_count < 10:
        raise SystemExit("Smoke test failed: expected at least 10 candles")

    print("M2 smoke test passed")


if __name__ == "__main__":
    main()
'@

Write-ProjectFile "analyzer\README.md" @'
# Analyzer M2

This is the M2 backend for Visual Trading Browser.

## Goal

FastAPI + OpenCV service that receives chart frames and converts visual candle pixels into `VisualCandle` objects.

This phase is still prediction-only:

- no CALL/PUT click
- no account credential access
- no cookie export
- no platform private API use
- no real strategy lock yet

Timing, locking, result resolver, and accuracy will be finalized in later milestones.

## Run

From the project root:

```powershell
npm run analyzer:setup
npm run analyzer:dev
```

Or directly:

```powershell
.\.venv\Scripts\python.exe -m uvicorn analyzer.app.main:app --host 127.0.0.1 --port 8000 --reload
```

## Test

Open this in the browser after running:

```text
http://127.0.0.1:8000/health
```

API docs:

```text
http://127.0.0.1:8000/docs
```
'@

Write-ProjectFile "scripts\setup-analyzer.ps1" @'
param(
  [string]$ProjectDir = (Split-Path $PSScriptRoot -Parent)
)

$ErrorActionPreference = "Stop"
Set-Location $ProjectDir

Write-Host "[M2] Setting up Python analyzer in: $ProjectDir" -ForegroundColor Cyan

$pythonExe = $null
$pythonArgs = @()

if (Get-Command py -ErrorAction SilentlyContinue) {
  $pythonExe = "py"
  $pythonArgs = @("-3")
} elseif (Get-Command python -ErrorAction SilentlyContinue) {
  $pythonExe = "python"
  $pythonArgs = @()
} else {
  throw "Python is not installed or not available in PATH. Install Python 3.11+ first."
}

if (-not (Test-Path ".venv\Scripts\python.exe")) {
  Write-Host "[M2] Creating .venv..." -ForegroundColor Cyan
  & $pythonExe @pythonArgs -m venv .venv
}

$venvPython = Join-Path $ProjectDir ".venv\Scripts\python.exe"

Write-Host "[M2] Upgrading pip..." -ForegroundColor Cyan
& $venvPython -m pip install --upgrade pip

Write-Host "[M2] Installing analyzer requirements..." -ForegroundColor Cyan
& $venvPython -m pip install -r "analyzer\requirements.txt"

Write-Host "[M2] Running OpenCV smoke test..." -ForegroundColor Cyan
& $venvPython -m analyzer.tools.smoke_test

Write-Host "[OK] Analyzer setup complete." -ForegroundColor Green
'@

Write-ProjectFile "scripts\run-analyzer.ps1" @'
param(
  [string]$ProjectDir = (Split-Path $PSScriptRoot -Parent),
  [int]$Port = 8000
)

$ErrorActionPreference = "Stop"
Set-Location $ProjectDir

if (-not (Test-Path ".venv\Scripts\python.exe")) {
  Write-Host "[M2] .venv missing. Running setup first..." -ForegroundColor Yellow
  & powershell -ExecutionPolicy Bypass -File "scripts\setup-analyzer.ps1" -ProjectDir $ProjectDir
}

$venvPython = Join-Path $ProjectDir ".venv\Scripts\python.exe"

Write-Host "[M2] Starting analyzer at http://127.0.0.1:$Port" -ForegroundColor Cyan
Write-Host "[M2] Health: http://127.0.0.1:$Port/health" -ForegroundColor Cyan
Write-Host "[M2] Docs:   http://127.0.0.1:$Port/docs" -ForegroundColor Cyan

& $venvPython -m uvicorn analyzer.app.main:app --host 127.0.0.1 --port $Port --reload
'@

Write-ProjectFile "scripts\test-analyzer-health.ps1" @'
param(
  [int]$Port = 8000
)

$ErrorActionPreference = "Stop"
$url = "http://127.0.0.1:$Port/health"
Write-Host "[M2] Testing $url" -ForegroundColor Cyan
$response = Invoke-RestMethod -Uri $url -Method Get
$response | ConvertTo-Json -Depth 20
'@

# Update package.json scripts without touching existing dependencies.
$packageJsonPath = Join-Path $ProjectDir "package.json"
if (Test-Path $packageJsonPath) {
  Backup-ExistingFile $packageJsonPath
  $pkg = Get-Content -Raw $packageJsonPath | ConvertFrom-Json

  if (-not $pkg.PSObject.Properties.Name.Contains("scripts") -or $null -eq $pkg.scripts) {
    $pkg | Add-Member -NotePropertyName scripts -NotePropertyValue ([pscustomobject]@{}) -Force
  }

  $pkg.scripts | Add-Member -NotePropertyName "analyzer:setup" -NotePropertyValue "powershell -ExecutionPolicy Bypass -File scripts/setup-analyzer.ps1" -Force
  $pkg.scripts | Add-Member -NotePropertyName "analyzer:dev" -NotePropertyValue "powershell -ExecutionPolicy Bypass -File scripts/run-analyzer.ps1" -Force
  $pkg.scripts | Add-Member -NotePropertyName "analyzer:health" -NotePropertyValue "powershell -ExecutionPolicy Bypass -File scripts/test-analyzer-health.ps1" -Force
  $pkg.scripts | Add-Member -NotePropertyName "analyzer:smoke" -NotePropertyValue ".venv\\Scripts\\python.exe -m analyzer.tools.smoke_test" -Force

  $pkg | ConvertTo-Json -Depth 100 | Set-Content -Path $packageJsonPath -Encoding UTF8
  Write-Ok "Updated package.json analyzer scripts"
} else {
  Write-Warn "package.json not found. Analyzer files were still created."
}

Write-Ok "M2 FastAPI + OpenCV analyzer files added."
Write-Host ""
Write-Host "Next commands:" -ForegroundColor Cyan
Write-Host "  npm run analyzer:setup" -ForegroundColor White
Write-Host "  npm run analyzer:dev" -ForegroundColor White
Write-Host ""

if ($Install) {
  Write-Info "Running analyzer setup now..."
  & powershell -ExecutionPolicy Bypass -File "scripts\setup-analyzer.ps1" -ProjectDir $ProjectDir
}

if ($RunAnalyzer) {
  Write-Info "Starting analyzer now..."
  & powershell -ExecutionPolicy Bypass -File "scripts\run-analyzer.ps1" -ProjectDir $ProjectDir
}
