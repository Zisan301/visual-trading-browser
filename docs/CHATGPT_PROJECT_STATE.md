# ChatGPT Project State - Visual Trading Browser

Last updated: 2026-07-30 13:51 Bangladesh time

## Project location

E:\VS Code\visual-trading-browser

## GitHub repository

https://github.com/Zisan301/visual-trading-browser.git

## Main goal

Build a prediction-only Electron desktop browser that opens Quotex or another trading platform, captures the candlestick chart visually, sends frames to a local Python FastAPI/OpenCV analyzer, detects candles, tracks the running candle, prepares timing states, and later runs strategy rules.

## Safety rules

This project must remain prediction-only.

It must NOT:

- click CALL or PUT
- place trades
- read private platform APIs
- export cookies
- store passwords
- bypass CAPTCHA
- modify locked predictions after the lock window

## Completed milestones

### M1 - Electron browser shell

Status: DONE

Implemented:

- Electron desktop app
- BaseWindow
- Separate WebContentsView for platform
- Separate WebContentsView for local dashboard
- Persistent platform session
- Safe remote platform settings
- Browser controls: Go, Back, Forward, Reload
- Scanner Start and Stop buttons
- Capture preview
- Basic browser-side timing display

### M2.1 - Electron to FastAPI analyzer connection

Status: DONE

Implemented:

- electron/analyzer-client.ts
- WebSocket connection from Electron to analyzer
- WebSocket URL: ws://127.0.0.1:8000/ws/analyze
- Electron sends captured PNG frames as base64
- Dashboard shows analyzer connection status
- Dashboard shows analyzer result
- Last sequence increases
- analyzer sent: yes works

Proof seen earlier:

- Analyzer status: CONNECTED
- Last sequence increasing
- analyzer sent: yes

### M2.2 - Chart-only capture crop

Status: DONE

Implemented:

- Electron captures a chart-focused region instead of the full platform page
- Dashboard shows latest chart-only frame
- Dashboard shows crop rect and crop size
- Current Quotex crop is usable

Current crop in electron/main.ts:

- xRatio: 0.14
- yRatio: 0.19
- widthRatio: 0.53
- heightRatio: 0.68

### M2.3 - Candle detector stability

Status: DONE

Implemented:

- OpenCV detector improved
- Reduced x-column candle merging
- Ignored huge fake vertical bars
- Smoke test passes
- Live chart confidence improved

Proof seen earlier:

- Smoke test detected candles: 25
- Smoke test confidence: 0.949
- Live dashboard reached about 20 candles
- Live detector confidence reached about 90 percent

### M2.4 - Live candle tracker

Status: DONE

Implemented:

- analyzer/app/tracking/candle_tracker.py
- Added tracking field in analyzer response
- FastAPI analyzer uses LiveCandleTracker
- Dashboard JSON shows tracking object
- Stable running candle IDs work

Proof seen earlier:

- Health phase: M2_4_LIVE_CANDLE_TRACKER
- running_candle_id: LIVE_CANDLE_000003
- frames_in_current: 92
- total_rollovers: 2
- last_closed_candle_id: LIVE_CANDLE_000002

## Current active milestone

### M2.5 - Timing state machine

Status: STARTED BUT NOT CONFIRMED COMPLETE

Important: The M2.5 timing state machine code was given, but the final test output was not confirmed yet in chat.

Need to check next time:

- Did analyzer/app/prediction/timing_state_machine.py get created?
- Did analyzer/app/main.py get updated to phase M2_5_TIMING_STATE_MACHINE?
- Did electron/analyzer-client.ts send candle_second and candle_remaining?
- Did electron/main.ts send candleSecond and candleRemaining?
- Did renderer/index.html show analyzer_timing in the JSON box?
- Did npm run analyzer:health show phase M2_5_TIMING_STATE_MACHINE?
- Did npm run analyzer:smoke pass?
- Did npm run build:electron pass?
- Did dashboard JSON show analyzer_timing?

Expected analyzer_timing output:

- machine: M2_5_TIMING_STATE_MACHINE
- state: OBSERVING or FORMING_SCAN or LOCK_WINDOW or LOCKED
- cycle_number
- candle_second
- candle_remaining
- lock_window_open
- lock_ready
- locked_this_candle
- locked_sequence
- no_signal_reason: Strategy engine not implemented yet

## Exact continuation point

Continue from M2.5 Timing State Machine.

Do NOT redo:

- M1 browser shell
- M2.1 WebSocket connection
- M2.2 chart crop
- M2.3 candle detector improvement
- M2.4 live candle tracker

First task next time:

1. Run scripts/project-checkpoint.ps1
2. Run git status --short
3. Run npm run analyzer:health
4. Run npm run analyzer:smoke
5. Run npm run build:electron
6. If M2.5 is not fully working, finish or fix M2.5
7. If M2.5 works, commit it and move to M2.6 strategy rule engine skeleton

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

## Important notes

npm run analyzer:dev is a server command. It keeps running and should not finish.

npm run analyzer:health works only when analyzer:dev is running.

If dashboard says CONNECTING and analyzer sent: no, start analyzer:dev, then Stop scanner and Start scanner again.

If Python cache files appear in git status, clean them:

git ls-files | Where-Object { $_. -match '(__pycache__|\.pyc$|\.pyo$)' }

Better command:

git ls-files | Where-Object { $_ -match '(__pycache__|\.pyc$|\.pyo$)' } | ForEach-Object { git rm --cached -- $_ }

## Next message to ChatGPT

Continue from docs/CHATGPT_PROJECT_STATE.md. M2.4 live candle tracker is done. M2.5 timing state machine was started but not confirmed complete. First verify M2.5, then continue.
