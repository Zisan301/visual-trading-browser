Set-Location "E:\VS Code\visual-trading-browser"

Write-Host ""
Write-Host "=== Visual Trading Browser Checkpoint ==="
Write-Host ""

Write-Host "Git branch:"
git branch --show-current

Write-Host ""
Write-Host "Git status:"
git status --short

Write-Host ""
Write-Host "Recent commits:"
git log --oneline -5

Write-Host ""
Write-Host "Next file to read:"
Write-Host "docs/CHATGPT_PROJECT_STATE.md"

Write-Host ""
Write-Host "Next task:"
Write-Host "M2.4 - Live candle tracker is NOT done yet."
