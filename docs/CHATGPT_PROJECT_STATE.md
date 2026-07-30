# ChatGPT Project State - Visual Trading Browser

Last updated: 2026-07-30 13:45 Bangladesh time

## Current project path

E:\VS Code\visual-trading-browser

## GitHub repo

https://github.com/Zisan301/visual-trading-browser.git

## Completed milestones

### M1 - Electron browser shell

Completed.

- Electron desktop app
- BaseWindow
- Platform WebContentsView
- Dashboard WebContentsView
- Persistent platform session
- Safe remote platform settings
- Browser navigation controls
- Scanner start/stop
- Capture preview
- Basic phase display

### M2.1 - Electron to FastAPI analyzer connection

Completed.

- Electron sends captured frames to FastAPI through WebSocket
- WebSocket URL: ws://127.0.0.1:8000/ws/analyze
- Analyzer status visible in dashboard
- Analyzer result visible in dashboard
- Sequence increases correctly
- analyzer sent: yes works

### M2.2 - Chart-only crop

Completed.

- Electron captures chart-focused region instead of full platform view
- Dashboard shows chart-only preview
- Dashboard shows crop rect and crop size
- Current Quotex crop is usable

Current crop in electron/main.ts:

xRatio: 0.14
yRatio: 0.19
widthRatio: 0.53
heightRatio: 0.68

### M2.3 - Candle detector stability

Completed.

- Detector now avoids excessive x-column merging
- Detector ignores huge fake vertical bars
- Smoke test passes
- Live chart result reached around:
  - Candles detected: 20+
  - Detector confidence: 90%+

### M2.4 - Live candle tracker

Completed.

Implemented:

- analyzer/app/tracking/candle_tracker.py
- tracking output in AnalysisResponse
- FastAPI analyzer uses LiveCandleTracker
- Dashboard JSON shows tracking object
- Stable running candle IDs:
  - LIVE_CANDLE_000001
  - LIVE_CANDLE_000002
  - LIVE_CANDLE_000003
- Tracker fields:
  - tracker_ready
  - running_candle_id
  - current_started_sequence
  - frames_in_current
  - rollover_detected
  - last_rollover_sequence
  - total_rollovers
  - last_closed_candle_id
  - current_x_center
  - previous_x_center
  - estimated_spacing_px

Working proof:

- Health phase: M2_4_LIVE_CANDLE_TRACKER
- Smoke test passed
- Build passed
- Dashboard showed:
  - running_candle_id: LIVE_CANDLE_000003
  - frames_in_current: 92
  - total_rollovers: 2
  - last_closed_candle_id: LIVE_CANDLE_000002

## Current next task

M2.5 - Timing state machine.

Goal:

Create proper analyzer-side candle phase logic:

- OBSERVING
- FORMING_SCAN
- LOCK_WINDOW
- LOCKED
- TARGET_RUNNING
- RESOLVING
- COOLDOWN

Important:

No real strategy prediction yet.
No CALL/PUT click.
No trading action.

M2.5 should only prepare the timing state so later strategies can lock predictions fairly.

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

## How to resume next time

Tell ChatGPT:

Continue from docs/CHATGPT_PROJECT_STATE.md. M2.4 live candle tracker is done. Start M2.5 timing state machine.
