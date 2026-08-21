# ================================================================
# Church Digital Platform ? Local Test Apps Server Runner
# ================================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  ? Church Digital Platform ? Local Test Apps Launcher" -ForegroundColor Yellow
Write-Host "================================================================" -ForegroundColor Cyan

$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) {
    Write-Host "[ERROR] Node.js is not found in PATH." -ForegroundColor Red
    Write-Host "Please install Node.js to run the local test apps server." -ForegroundColor Red
    exit 1
}

$port = 3000
$serveScript = Join-Path $PSScriptRoot "serve.js"

# ----------------------------------------------------------------
# FR-006: generate per-run passwords (never committed) and sync them
# into local auth.users so seeded logins work with fresh secrets.
# ----------------------------------------------------------------
$phones = @(
    '+201000000001',
    '+201000000002',
    '+201000000003',
    '+201000000004',
    '+201000000005'
)
$creds = [ordered]@{}
foreach ($p in $phones) {
    $bytes = New-Object byte[] 18
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $creds[$p] = [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+','x').Replace('/','y')
}
$credsPath = Join-Path $PSScriptRoot "shared\.local-credentials.json"
$creds | ConvertTo-Json | Set-Content -Path $credsPath -Encoding UTF8
Write-Host "  ? Generated per-run credentials -> shared/.local-credentials.json (gitignored)" -ForegroundColor Green

$dbUp = docker ps --format "{{.Names}}" 2>$null | Select-String -Quiet -Pattern "^supabase_db_church$"
if ($dbUp) {
    foreach ($p in $phones) {
        $safePwd = $creds[$p].Replace("'", "''")
        $sql = "update auth.users set encrypted_password = crypt('$safePwd', gen_salt('bf')) where phone = '$p';"
        $sql | docker exec -i supabase_db_church psql -U postgres -d postgres -v ON_ERROR_STOP=1 2>$null | Out-Null
    }
    Write-Host "  ? Synced generated passwords into local auth.users" -ForegroundColor Green
} else {
    Write-Host "  ? supabase_db_church container not running; passwords not synced." -ForegroundColor Yellow
}

# ----------------------------------------------------------------
# FR-006 gate: refuse to start if credential literals exist in
# committed files (generated credentials file is excluded).
# ----------------------------------------------------------------
$literalHits = Get-ChildItem $PSScriptRoot -Recurse -File -Include *.js, *.html |
    Where-Object { $_.Name -ne '.local-credentials.json' } |
    Select-String -Pattern 'password123|InNlcnZpY2Vfcm9sZSI' -List
if ($literalHits) {
    Write-Host "[ERROR] Credential literals found in committed files:" -ForegroundColor Red
    $literalHits | ForEach-Object { Write-Host "  - $($_.Path):$($_.LineNumber)" -ForegroundColor Red }
    exit 1
}
Write-Host "  ? Credential literal scan clean" -ForegroundColor Green

Write-Host "Checking local Supabase stack on http://127.0.0.1:54321 ..." -ForegroundColor DarkGray
try {
    $sbCheck = Invoke-WebRequest -Uri "http://127.0.0.1:54321/rest/v1/" -Headers @{ apikey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0" } -UseBasicParsing -TimeoutSec 2
    Write-Host "  ? Supabase REST API is ONLINE (HTTP $($sbCheck.StatusCode))" -ForegroundColor Green
} catch {
    Write-Host "  ? Supabase stack not responding at 54321. Run 'npx supabase start' if needed." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Launching Browser at http://127.0.0.1:$port/ ..." -ForegroundColor Green
Start-Process "http://127.0.0.1:$port/"

Write-Host "Starting Node.js HTTP server..." -ForegroundColor Cyan
& node $serveScript $port

