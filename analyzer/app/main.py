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
