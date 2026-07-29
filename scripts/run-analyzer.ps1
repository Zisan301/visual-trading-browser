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
