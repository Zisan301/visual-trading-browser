from __future__ import annotations

import json
import time
from typing import Any

from fastapi import FastAPI, File, Form, HTTPException, UploadFile, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware

from analyzer.app.capture.frame_receiver import FrameDecodeError, decode_base64_image, decode_image_bytes
from analyzer.app.capture.frame_validator import FrameValidationError, validate_frame
from analyzer.app.prediction.timing_state_machine import TimingStateMachine
from analyzer.app.prediction.prediction_lock import PredictionLockManager
from analyzer.app.prediction.signal_history import SignalHistoryTracker
from analyzer.app.schemas import AnalysisResponse, FrameMetadata
from analyzer.app.tracking.candle_tracker import LiveCandleTracker
from analyzer.app.vision.candle_detector import VisualCandleDetector

app = FastAPI(
    title="Visual Trading Browser Analyzer",
    version="0.3.0",
    description="M3.0 FastAPI + OpenCV visual candle detector with stable signal panel. Prediction-only. No trading actions.",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://127.0.0.1", "http://localhost", "file://"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

_detector = VisualCandleDetector()
_tracker = LiveCandleTracker()
_timing_machine = TimingStateMachine()
_prediction_lock = PredictionLockManager()
_signal_history = SignalHistoryTracker()


@app.get("/health")
def health() -> dict[str, Any]:
    return {
        "ok": True,
        "service": "visual-trading-browser-analyzer",
        "phase": "M3_0_STABLE_SIGNAL_PANEL",
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
        result = _analyze_and_track(image, metadata=metadata, sequence=metadata.frame_sequence)
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
                result = _analyze_and_track(image, metadata=metadata, sequence=metadata.frame_sequence)
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


def _analyze_and_track(image: Any, metadata: FrameMetadata | None = None, sequence: int = 0) -> AnalysisResponse:
    metadata = metadata or FrameMetadata(frame_sequence=sequence)

    result = _detector.analyze_image(image, sequence=sequence)
    tracked = _tracker.update(result)

    candle_second = metadata.candle_second
    candle_remaining = metadata.candle_remaining

    # M2.6 hard fallback: if Electron metadata is missing, use server wall-clock second.
    # This prevents candle_second/candle_remaining from staying null and allows lock-window testing.
    if candle_second is None:
        candle_second = int(time.time()) % 60

    if candle_remaining is None:
        candle_remaining = max(0, 60 - int(candle_second))

    analyzer_timing = _timing_machine.update(
        sequence=tracked.sequence,
        candle_second=candle_second,
        candle_remaining=candle_remaining,
        tracking=tracked.tracking,
    )

    current_candle_payload = tracked.current_candle.model_dump() if tracked.current_candle else None

    prediction_lock = _prediction_lock.update(
        sequence=tracked.sequence,
        timing=analyzer_timing,
        current_candle=current_candle_payload,
        tracking=tracked.tracking,
    )

    signal_history = _signal_history.update(
        sequence=tracked.sequence,
        prediction_lock=prediction_lock,
        tracking=tracked.tracking,
        current_candle=current_candle_payload,
    )

    signals = list(tracked.signals or [])
    if prediction_lock.get("signal"):
        signals.append(prediction_lock["signal"])

    market = dict(tracked.market or {})
    market["prediction_lock"] = prediction_lock
    market["signal_history"] = signal_history

    return tracked.model_copy(
        update={
            "timing": analyzer_timing,
            "analyzer_timing": analyzer_timing,
            "market": market,
            "signals": signals,
        }
    )


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









