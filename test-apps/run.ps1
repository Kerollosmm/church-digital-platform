# ================================================================
# Church Digital Platform — Local Test Apps Server Runner
# ================================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  ✝ Church Digital Platform — Local Test Apps Launcher" -ForegroundColor Yellow
Write-Host "================================================================" -ForegroundColor Cyan

$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) {
    Write-Host "[ERROR] Node.js is not found in PATH." -ForegroundColor Red
    Write-Host "Please install Node.js to run the local test apps server." -ForegroundColor Red
    exit 1
}

$port = 3000
$serveScript = Join-Path $PSScriptRoot "serve.js"

Write-Host "Checking local Supabase stack on http://127.0.0.1:54321 ..." -ForegroundColor DarkGray
try {
    $sbCheck = Invoke-WebRequest -Uri "http://127.0.0.1:54321/rest/v1/" -Headers @{ apikey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" } -UseBasicParsing -TimeoutSec 2
    Write-Host "  ✓ Supabase REST API is ONLINE (HTTP $($sbCheck.StatusCode))" -ForegroundColor Green
} catch {
    Write-Host "  ⚠ Supabase stack not responding at 54321. Run 'npx supabase start' if needed." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Launching Browser at http://127.0.0.1:$port/ ..." -ForegroundColor Green
Start-Process "http://127.0.0.1:$port/"

Write-Host "Starting Node.js HTTP server..." -ForegroundColor Cyan
& node $serveScript $port
