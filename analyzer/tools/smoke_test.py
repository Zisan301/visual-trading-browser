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
