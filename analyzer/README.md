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
