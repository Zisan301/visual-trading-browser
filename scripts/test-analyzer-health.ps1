param(
  [int]$Port = 8000
)

$ErrorActionPreference = "Stop"
$url = "http://127.0.0.1:$Port/health"
Write-Host "[M2] Testing $url" -ForegroundColor Cyan
$response = Invoke-RestMethod -Uri $url -Method Get
$response | ConvertTo-Json -Depth 20
