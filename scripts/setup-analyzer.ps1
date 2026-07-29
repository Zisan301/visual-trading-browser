param(
  [string]$ProjectDir = (Split-Path $PSScriptRoot -Parent)
)

$ErrorActionPreference = "Stop"
Set-Location $ProjectDir

Write-Host "[M2] Setting up Python analyzer in: $ProjectDir" -ForegroundColor Cyan

$pythonExe = $null
$pythonArgs = @()

if (Get-Command py -ErrorAction SilentlyContinue) {
  $pythonExe = "py"
  $pythonArgs = @("-3")
} elseif (Get-Command python -ErrorAction SilentlyContinue) {
  $pythonExe = "python"
  $pythonArgs = @()
} else {
  throw "Python is not installed or not available in PATH. Install Python 3.11+ first."
}

if (-not (Test-Path ".venv\Scripts\python.exe")) {
  Write-Host "[M2] Creating .venv..." -ForegroundColor Cyan
  & $pythonExe @pythonArgs -m venv .venv
}

$venvPython = Join-Path $ProjectDir ".venv\Scripts\python.exe"

Write-Host "[M2] Upgrading pip..." -ForegroundColor Cyan
& $venvPython -m pip install --upgrade pip

Write-Host "[M2] Installing analyzer requirements..." -ForegroundColor Cyan
& $venvPython -m pip install -r "analyzer\requirements.txt"

Write-Host "[M2] Running OpenCV smoke test..." -ForegroundColor Cyan
& $venvPython -m analyzer.tools.smoke_test

Write-Host "[OK] Analyzer setup complete." -ForegroundColor Green
