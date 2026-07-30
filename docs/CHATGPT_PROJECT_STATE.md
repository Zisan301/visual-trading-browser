# ChatGPT Project State - Visual Trading Browser

Last updated: 2026-07-30 13:00 Bangladesh time

## Repository

Project path on PC:

E:\VS Code\visual-trading-browser

GitHub repo:

https://github.com/Zisan301/visual-trading-browser.git

## Main project goal

Build a custom Electron desktop browser that opens a trading platform, visually captures the candlestick chart, sends chart frames to a local Python FastAPI/OpenCV analyzer, detects candles, tracks live candle state, and later generates prediction-only strategy signals.

Important safety rule:

This project must remain prediction-only. It must not click CALL/PUT, place trades, read private platform APIs, export cookies, store passwords, or bypass CAPTCHA.

## Completed work

### M1 - Electron browser shell

Completed.

Implemented:

- Electron desktop app
- BaseWindow
- Separate WebContentsView for platform
- Separate local dashboard view
- Persistent platform session
- Safe remote platform settings
- Browser controls:
  - Go
  - Back
  - Forward
  - Reload
- Scanner button
- Capture preview
- Basic timing phase:
  - OBSERVING
  - FORMING_SCAN
  - LOCK_WINDOW

### M2.1 - Electron scanner connected to Python analyzer

Completed.

Implemented:

- analyzer-client.ts
- WebSocket connection from Electron to FastAPI
- WebSocket URL:
  ws://127.0.0.1:8000/ws/analyze
- Electron sends captured PNG frames as base64
- Analyzer connection status appears in dashboard
- Analyzer result appears in dashboard
- Last sequence increases correctly
- "analyzer sent: yes" works

Working proof from dashboard:

- Status: CONNECTED
- Analyzer sent: yes
- Last sequence increasing

### M2.2 - Chart-only crop

Completed.

Implemented:

- Electron no longer sends full platform view
- Electron captures a chart-focused crop region
- Dashboard shows:
  - latest chart-only frame
  - crop rect
  - chart crop size
- Current crop is usable for Quotex

Current crop in electron/main.ts:

xRatio: 0.14
yRatio: 0.19
widthRatio: 0.53
heightRatio: 0.68

This crop avoids most of the left sidebar, top header, and right trade panel.

### M2.3 - Candle detector stability improvement

Completed enough for current checkpoint.

Implemented:

- Reduced x-column merge behavior
- Reduced false merging between close candles
- Ignored very tall fake vertical bars
- Smoke test passes

Smoke test result:

Detected candles: 25
Detector confidence: 0.949
M2 smoke test passed

Live Quotex dashboard result after improvement:

- Chart found: YES
- Candles detected: 20
- Detector confidence: 90%
- Current candle direction detected
- Analyzer connection stable

## Current Git state at last checkpoint

Current branch:

m2.4-live-candle-tracker

Recent commits:

a7b38cf Improve chart crop and candle detection stability
644bf16 Connect Electron scanner to FastAPI analyzer
6857438 Save project progress

Important:

Live candle tracker has NOT been implemented yet.

There was one dirty file:

analyzer/app/vision/__pycache__/candle_detector.cpython-313.pyc

This is Python cache. It should be removed from Git tracking before continuing.

## What NOT to redo

Do not redo these unless broken:

- M1 Electron shell
- WebSocket analyzer connection
- Chart crop system
- Basic OpenCV candle detector patch
- Dashboard analyzer status
- Dashboard detector result

## Next exact task

Start from:

M2.4 - Live candle tracker

Goal:

Detected candles are currently frame-by-frame. The analyzer does not yet know that the rightmost candle across multiple frames is the same running candle.

Need to implement:

- analyzer/app/tracking/candle_tracker.py
- Add tracking output to schemas.py
- Use tracker inside analyzer/app/main.py
- Show tracking JSON in dashboard
- Stable current candle ID:
  LIVE_CANDLE_000001
  LIVE_CANDLE_000002
- Track:
  - tracker_ready
  - running_candle_id
  - frames_in_current
  - rollover_detected
  - total_rollovers
  - last_closed_candle_id
  - current_x_center
  - previous_x_center
  - estimated_spacing_px

Acceptance test:

1. Start analyzer.
2. Run Electron app.
3. Open Quotex chart.
4. Click Start scanner.
5. JSON box should show tracking object.
6. frames_in_current should increase while same candle is running.
7. When new candle appears, rollover_detected should become true briefly.
8. running_candle_id should increment.

## How to resume next time

First run:

git status --short
git log --oneline -5

Then clean Python cache if needed:

git ls-files | Where-Object { $_ -match '(__pycache__|\.pyc$|\.pyo$)' } | ForEach-Object {
  git rm --cached -- $_
}

Then continue with M2.4 live candle tracker.

## Normal run commands

Start analyzer in one PowerShell:

Set-Location "E:\VS Code\visual-trading-browser"
npm run analyzer:dev

In another PowerShell:

Set-Location "E:\VS Code\visual-trading-browser"
npm run analyzer:health
npm run analyzer:smoke
npm run build:electron
npm run dev

## Known important behavior

npm run analyzer:dev is a server command. It runs continuously and should not finish. Keep that PowerShell window open.

npm run analyzer:health only works when analyzer:dev is already running.

If dashboard says CONNECTING and analyzer sent: no, analyzer server is probably not running. Start analyzer:dev, then stop/start scanner again.

## Next instruction for ChatGPT

Continue from M2.4 live candle tracker. Do not redo M2.1/M2.2/M2.3. First clean pycache tracking, then add the tracker.
