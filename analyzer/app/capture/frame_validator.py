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
