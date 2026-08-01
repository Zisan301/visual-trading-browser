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
$mainM25 = HasText "analyzer/app/main.py" "M3_0_STABLE_SIGNAL_PANEL"
$mainTiming = HasText "analyzer/app/main.py" "TimingStateMachine"
$timingInstance = HasText "analyzer/app/main.py" "_timing_machine = TimingStateMachine()"
$schemaSecond = HasText "analyzer/app/schemas.py" "candle_second"
$schemaRemain = HasText "analyzer/app/schemas.py" "candle_remaining"
$schemaAnalyzerTiming = HasText "analyzer/app/schemas.py" "analyzer_timing"
$electronSecond = HasText "electron/main.ts" "candleSecond"
$clientSecond = HasText "electron/analyzer-client.ts" "candle_second"
$rendererTiming = HasText "renderer/index.html" "analyzer_timing"
$predictionLockFile = Exists "analyzer/app/prediction/prediction_lock.py"
$mainPredictionLock = HasText "analyzer/app/main.py" "PredictionLockManager"
$rendererPredictionLock = HasText "renderer/index.html" "predictionLockStatus"
$strategyScoringFile = Exists "analyzer/app/prediction/strategy_scoring.py"
$predictionLockStrategy = HasText "analyzer/app/prediction/prediction_lock.py" "StrategyScoringEngine"
$rendererStrategyScore = HasText "renderer/index.html" "lockedStrategyScore"
$signalHistoryFile = Exists "analyzer/app/prediction/signal_history.py"
$mainSignalHistory = HasText "analyzer/app/main.py" "SignalHistoryTracker"
$rendererSignalHistory = HasText "renderer/index.html" "signalHistoryCard"
$outcomeResolverFile = Exists "analyzer/app/prediction/candle_outcome_resolver.py"
$signalHistoryResolver = HasText "analyzer/app/prediction/signal_history.py" "CandleOutcomeResolver"
$rendererOutcomeAccuracy = HasText "renderer/index.html" "accuracyPercent"
$mainM30 = HasText "analyzer/app/main.py" "M3_0_STABLE_SIGNAL_PANEL"
$historyM30 = HasText "analyzer/app/prediction/signal_history.py" "M3_0_STABLE_SIGNAL_PANEL"
$rendererM30 = HasText "renderer/index.html" "stableSignalPanelCard"

$next = @()

if ($status.Trim().Length -gt 0) { $next += "Uncommitted changes exist. Test, then commit/push." }
if ($timingFile -ne "YES") { $next += "Create analyzer/app/prediction/timing_state_machine.py." }
if ($mainM25 -ne "YES" -or $mainTiming -ne "YES" -or $timingInstance -ne "YES") { $next += "Fix M2.7 backend wiring in analyzer/app/main.py." }
if ($schemaSecond -ne "YES" -or $schemaRemain -ne "YES" -or $schemaAnalyzerTiming -ne "YES") { $next += "Fix analyzer/app/schemas.py metadata/analyzer_timing fields." }
if ($electronSecond -ne "YES" -or $clientSecond -ne "YES") { $next += "Fix Electron timing metadata passthrough." }
if ($rendererTiming -ne "YES") { $next += "Fix dashboard analyzer_timing display." }
if ($predictionLockFile -ne "YES" -or $mainPredictionLock -ne "YES") { $next += "Fix M2.6 prediction lock backend wiring." }
if ($rendererPredictionLock -ne "YES") { $next += "Fix M2.6 prediction lock dashboard display." }
if ($strategyScoringFile -ne "YES" -or $predictionLockStrategy -ne "YES") { $next += "Fix M2.7 strategy scoring backend wiring." }
if ($rendererStrategyScore -ne "YES") { $next += "Fix M2.7 strategy score dashboard display." }
if ($signalHistoryFile -ne "YES" -or $mainSignalHistory -ne "YES") { $next += "Fix M2.8 signal history backend wiring." }
if ($rendererSignalHistory -ne "YES") { $next += "Fix M2.8 signal history dashboard display." }
if ($outcomeResolverFile -ne "YES" -or $signalHistoryResolver -ne "YES") { $next += "Fix M2.9 candle outcome resolver backend wiring." }
if ($rendererOutcomeAccuracy -ne "YES") { $next += "Fix M2.9 accuracy dashboard display." }
if ($mainM30 -ne "YES" -or $historyM30 -ne "YES") { $next += "Fix M3.0 stable signal backend summary." }
if ($rendererM30 -ne "YES") { $next += "Fix M3.0 stable signal dashboard panel." }
if ($health -notmatch "M3_0_STABLE_SIGNAL_PANEL") { $next += "Restart analyzer or finish health phase M2.7 wiring." }

if ($next.Count -eq 0) {
    $next += "M2.6 looks structurally complete. Live-test one locked prediction per candle, then continue M2.7 strategy scoring placeholder."
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
main.py M2.7 phase: $mainM25
main.py TimingStateMachine: $mainTiming
main.py _timing_machine: $timingInstance
schemas.py candle_second: $schemaSecond
schemas.py candle_remaining: $schemaRemain
schemas.py analyzer_timing: $schemaAnalyzerTiming
electron/main.ts candleSecond: $electronSecond
electron/analyzer-client.ts candle_second: $clientSecond
renderer/index.html analyzer_timing: $rendererTiming

M2.6 checks:
prediction_lock.py: $predictionLockFile
main.py PredictionLockManager: $mainPredictionLock
renderer/index.html predictionLockStatus: $rendererPredictionLock

M2.7 checks:
strategy_scoring.py: $strategyScoringFile
prediction_lock.py StrategyScoringEngine: $predictionLockStrategy
renderer/index.html lockedStrategyScore: $rendererStrategyScore

M2.8 checks:
signal_history.py: $signalHistoryFile
main.py SignalHistoryTracker: $mainSignalHistory
renderer/index.html signalHistoryCard: $rendererSignalHistory

M2.9 checks:
candle_outcome_resolver.py: $outcomeResolverFile
signal_history.py CandleOutcomeResolver: $signalHistoryResolver
renderer/index.html accuracyPercent: $rendererOutcomeAccuracy

M3.0 checks:
main.py M3.0 phase: $mainM30
signal_history.py panel summary: $historyM30
renderer/index.html stableSignalPanelCard: $rendererM30

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






