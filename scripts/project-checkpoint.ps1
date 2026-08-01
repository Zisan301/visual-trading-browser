$ErrorActionPreference = "SilentlyContinue"

function YesNo($condition) {
    if ($condition) { return "YES" }
    return "NO"
}

function Exists($path) {
    return YesNo(Test-Path $path)
}

function HasText($path, $text) {
    if (!(Test-Path $path)) { return "NO" }
    $raw = Get-Content $path -Raw
    return YesNo($raw -like "*$text*")
}

$now = Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz"
$branch = git branch --show-current
$status = git status --short
$commits = git log --oneline --decorate -10

$health = ""
try {
    $healthObj = Invoke-RestMethod "http://127.0.0.1:8000/health" -TimeoutSec 2
    $health = ($healthObj | ConvertTo-Json -Compress)
} catch {
    $health = "Analyzer not running. Start with: npm run analyzer:dev"
}

$checks = [ordered]@{}

$checks["docs/CHATGPT_PROJECT_STATE.md"] = Exists "docs/CHATGPT_PROJECT_STATE.md"
$checks["docs/STRATEGY_LAYER_MEMORY.md"] = Exists "docs/STRATEGY_LAYER_MEMORY.md"

$checks["timing_state_machine.py"] = Exists "analyzer/app/prediction/timing_state_machine.py"
$checks["main.py TimingStateMachine"] = HasText "analyzer/app/main.py" "TimingStateMachine"
$checks["main.py PredictionLockManager"] = HasText "analyzer/app/main.py" "PredictionLockManager"
$checks["prediction_lock.py"] = Exists "analyzer/app/prediction/prediction_lock.py"

$checks["strategy_scoring.py"] = Exists "analyzer/app/prediction/strategy_scoring.py"
$checks["prediction_lock.py StrategyScoringEngine"] = HasText "analyzer/app/prediction/prediction_lock.py" "StrategyScoringEngine"

$checks["signal_history.py"] = Exists "analyzer/app/prediction/signal_history.py"
$checks["signal_history.py panel summary"] = HasText "analyzer/app/prediction/signal_history.py" "M3_0_STABLE_SIGNAL_PANEL"

$checks["candle_outcome_resolver.py"] = Exists "analyzer/app/prediction/candle_outcome_resolver.py"
$checks["signal_history.py CandleOutcomeResolver"] = HasText "analyzer/app/prediction/signal_history.py" "CandleOutcomeResolver"

$checks["renderer predictionLockStatus"] = HasText "renderer/index.html" "predictionLockStatus"
$checks["renderer signalHistoryCard"] = HasText "renderer/index.html" "signalHistoryCard"
$checks["renderer stableSignalPanelCard"] = HasText "renderer/index.html" "stableSignalPanelCard"
$checks["renderer signalTableCard"] = HasText "renderer/index.html" "signalTableCard"

$checks["electron/main.ts candleSecond"] = HasText "electron/main.ts" "candleSecond"
$checks["electron/analyzer-client.ts candle_second"] = HasText "electron/analyzer-client.ts" "candle_second"

$phase = "UNKNOWN"
if (Test-Path "analyzer/app/main.py") {
    $mainRaw = Get-Content "analyzer/app/main.py" -Raw
    if ($mainRaw -like "*M3_1_SIGNAL_TABLE_UI*") { $phase = "M3.1_SIGNAL_TABLE_UI" }
    elseif ($mainRaw -like "*M3_0_STABLE_SIGNAL_PANEL*") { $phase = "M3.0_STABLE_SIGNAL_PANEL" }
    elseif ($mainRaw -like "*M2_9_CANDLE_OUTCOME_RESOLVER*") { $phase = "M2.9_CANDLE_OUTCOME_RESOLVER" }
    elseif ($mainRaw -like "*M2_8_SIGNAL_HISTORY_TRACKER*") { $phase = "M2.8_SIGNAL_HISTORY_TRACKER" }
    elseif ($mainRaw -like "*M2_7_STRATEGY_SCORING_PLACEHOLDER*") { $phase = "M2.7_STRATEGY_SCORING_PLACEHOLDER" }
    elseif ($mainRaw -like "*M2_6_PREDICTION_LOCK_WINDOW*") { $phase = "M2.6_PREDICTION_LOCK_WINDOW" }
    elseif ($mainRaw -like "*M2_5_TIMING_STATE_MACHINE*") { $phase = "M2.5_TIMING_STATE_MACHINE" }
}

$next = New-Object System.Collections.Generic.List[string]

if ($status) {
    $next.Add("Uncommitted changes exist. Test, then commit/push.")
}

if ($checks["renderer signalTableCard"] -eq "YES" -and $phase -eq "M3.1_SIGNAL_TABLE_UI") {
    $next.Add("Continue with M3.2 Signal Export and Session Summary.")
} elseif ($checks["renderer stableSignalPanelCard"] -eq "YES") {
    $next.Add("Continue with M3.1 Signal Table UI or finish/merge it.")
} elseif ($checks["signal_history.py panel summary"] -eq "YES") {
    $next.Add("Continue with M3.0 Stable Signal Panel or finish it.")
} elseif ($checks["candle_outcome_resolver.py"] -eq "YES") {
    $next.Add("Continue with M2.9 Candle Outcome Resolver or finish it.")
} elseif ($checks["signal_history.py"] -eq "YES") {
    $next.Add("Continue with M2.8 Signal History Tracker or finish it.")
} elseif ($checks["strategy_scoring.py"] -eq "YES") {
    $next.Add("Continue with M2.7 Strategy Scoring Placeholder or finish it.")
} elseif ($checks["prediction_lock.py"] -eq "YES") {
    $next.Add("Continue with M2.6 Prediction Lock Window or finish it.")
} else {
    $next.Add("Continue from latest implemented milestone in docs/CHATGPT_PROJECT_STATE.md.")
}

if ($health -like "*Analyzer not running*") {
    $next.Add("Analyzer not running. For live test run: npm run analyzer:dev")
}

$checkText = ""
foreach ($item in $checks.GetEnumerator()) {
    $checkText += "$($item.Key): $($item.Value)`n"
}

$nextText = ""
foreach ($item in $next) {
    $nextText += "- $item`n"
}

$report = @"
=== Visual Trading Browser Checkpoint ===

Last updated:
$now

Current branch:
$branch

Detected phase:
$phase

Git status:
$(if ($status) { $status } else { "Working tree clean" })

Recent commits:
$commits

Analyzer health:
$health

Project checks:
$checkText

Project memory files:
- docs/CHATGPT_PROJECT_STATE.md
- docs/STRATEGY_LAYER_MEMORY.md

Strategy layer memory:
- Future M4 strategy layer will learn strategy ideas from professional videos, books, websites, and examples.
- Strategies will be converted into structured rules/features.
- A separate dataset-creation browser/tool will be built later.
- Live/replay data will create labeled datasets.
- Offline training/validation will decide which strategies enter the model.
- System remains prediction-only unless future safety/legal/manual-confirmation phases explicitly change it.

NEXT CONTINUATION TASK:
$nextText

Important next command:
Set-Location "E:\VS Code\visual-trading-browser"
powershell -ExecutionPolicy Bypass -File ".\scripts\project-checkpoint.ps1"

Then say:
Continue from docs/CHATGPT_PROJECT_STATE.md
"@

Set-Content -Path "docs/CHATGPT_PROJECT_STATE.md" -Value $report -Encoding UTF8

Write-Host $report
