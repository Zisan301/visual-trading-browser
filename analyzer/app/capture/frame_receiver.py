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
