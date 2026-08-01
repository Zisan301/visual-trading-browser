$ErrorActionPreference = "Continue"

Set-Location "E:\VS Code\visual-trading-browser"

function Run-Cmd {
    param([string]$Command)
    try {
        $out = cmd /c $Command 2>&1
        return ($out -join "`n")
    } catch {
        return "ERROR: $Command`n$($_.Exception.Message)"
    }
}

function HasText {
    param([string]$Path, [string]$Needle)
    if (!(Test-Path $Path)) { return "MISSING_FILE" }
    $txt = Get-Content $Path -Raw
    if ($txt.Contains($Needle)) { return "YES" }
    return "NO"
}

function Exists {
    param([string]$Path)
    if (Test-Path $Path) { return "YES" }
    return "NO"
}

$now = Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz"
$branch = Run-Cmd "git branch --show-current"
$status = Run-Cmd "git status --short"
$commits = Run-Cmd "git log --oneline --decorate -10"

try {
    $health = (Invoke-RestMethod -Uri "http://127.0.0.1:8000/health" -TimeoutSec 3 | ConvertTo-Json -Depth 10)
} catch {
    $health = "Analyzer not running. Start with: npm run analyzer:dev"
}

$timingFile = Exists "analyzer/app/prediction/timing_state_machine.py"
$mainM25 = HasText "analyzer/app/main.py" "M2_5_TIMING_STATE_MACHINE"
$mainTiming = HasText "analyzer/app/main.py" "TimingStateMachine"
$timingInstance = HasText "analyzer/app/main.py" "_timing_machine = TimingStateMachine()"
$schemaSecond = HasText "analyzer/app/schemas.py" "candle_second"
$schemaRemain = HasText "analyzer/app/schemas.py" "candle_remaining"
$schemaAnalyzerTiming = HasText "analyzer/app/schemas.py" "analyzer_timing"
$electronSecond = HasText "electron/main.ts" "candleSecond"
$clientSecond = HasText "electron/analyzer-client.ts" "candle_second"
$rendererTiming = HasText "renderer/index.html" "analyzer_timing"

$next = @()

if ($status.Trim().Length -gt 0) { $next += "Uncommitted changes exist. Test, then commit/push." }
if ($timingFile -ne "YES") { $next += "Create analyzer/app/prediction/timing_state_machine.py." }
if ($mainM25 -ne "YES" -or $mainTiming -ne "YES" -or $timingInstance -ne "YES") { $next += "Fix M2.5 backend wiring in analyzer/app/main.py." }
if ($schemaSecond -ne "YES" -or $schemaRemain -ne "YES" -or $schemaAnalyzerTiming -ne "YES") { $next += "Fix analyzer/app/schemas.py metadata/analyzer_timing fields." }
if ($electronSecond -ne "YES" -or $clientSecond -ne "YES") { $next += "Fix Electron timing metadata passthrough." }
if ($rendererTiming -ne "YES") { $next += "Fix dashboard analyzer_timing display." }
if ($health -notmatch "M2_5_TIMING_STATE_MACHINE") { $next += "Restart analyzer or finish health phase M2.5 wiring." }

if ($next.Count -eq 0) {
    $next += "M2.5 looks structurally complete. Next live-test OBSERVING -> FORMING_SCAN -> LOCK_WINDOW/LOCKED, then continue M2.6/M3 strategy placeholder."
}

$nextText = ($next | ForEach-Object { "- $_" }) -join "`n"

$report = @"
=== Visual Trading Browser Checkpoint ===

Last updated:
$now

Current branch:
$branch

Git status:
$status

Recent commits:
$commits

Analyzer health:
$health

M2.5 checks:
timing_state_machine.py: $timingFile
main.py M2.5 phase: $mainM25
main.py TimingStateMachine: $mainTiming
main.py _timing_machine: $timingInstance
schemas.py candle_second: $schemaSecond
schemas.py candle_remaining: $schemaRemain
schemas.py analyzer_timing: $schemaAnalyzerTiming
electron/main.ts candleSecond: $electronSecond
electron/analyzer-client.ts candle_second: $clientSecond
renderer/index.html analyzer_timing: $rendererTiming

NEXT CONTINUATION TASK:
$nextText

Important file:
docs/CHATGPT_PROJECT_STATE.md

Next time run:
Set-Location "E:\VS Code\visual-trading-browser"
powershell -ExecutionPolicy Bypass -File ".\scripts\project-checkpoint.ps1"

Then say:
Continue from docs/CHATGPT_PROJECT_STATE.md
"@

$report | Set-Content -Encoding UTF8 "docs/CHATGPT_PROJECT_STATE.md"
Write-Host $report
