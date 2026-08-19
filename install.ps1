# Sets up the Odoo connector for Claude Desktop on Windows.
# No admin rights needed - everything installs under the user's own profile.
#
# Identity is decided by .env:
#   no ODOO_API_KEY            -> ask the person for their own Odoo login
#   ODOO_PREFER_PERSONAL=true  -> ask, but fall back to the bundled key if that fails
#   otherwise                  -> use the bundled key, ask nothing
#
# The real work (config merge, path resolution) lives in setup_claude.py so it can be
# tested off-Windows; this script only installs uv and hands over.

$ErrorActionPreference = "Stop"
$RepoDir = $PSScriptRoot
$EnvFile = Join-Path $RepoDir ".env"

function Write-Step($msg) { Write-Host "-> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "OK $msg" -ForegroundColor Green }
function Write-Bad($msg)  { Write-Host "!! $msg" -ForegroundColor Red }

function Test-EnvFlag($pattern) {
    if (-not (Test-Path $EnvFile)) { return $false }
    return Select-String -Path $EnvFile -Pattern $pattern -Quiet
}

function Get-PowerShellExe {
    if (Get-Command powershell.exe -ErrorAction SilentlyContinue) { return "powershell.exe" }
    return "pwsh"
}

$HasKey = Test-EnvFlag '^ODOO_API_KEY=.+$'

# Hand over before the banner, so the personal installer doesn't print a second one.
if (-not $HasKey) {
    & (Get-PowerShellExe) -NoProfile -ExecutionPolicy Bypass -File (Join-Path $RepoDir "install-personal.ps1")
    exit $LASTEXITCODE
}

Write-Host ""
Write-Host "===  Odoo in Claude - Maj Andersen (RW) Ltd  ===" -ForegroundColor White
Write-Host ""

try {
    # --- 1. uv (installs its own Python, so this is the only prerequisite) ---
    $UserBin = Join-Path $env:USERPROFILE ".local\bin"
    if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
        if (Test-Path (Join-Path $UserBin "uv.exe")) {
            $env:Path = "$UserBin;$env:Path"
            Write-Ok "Found uv (already installed)"
        }
        else {
            Write-Step "Installing uv (one-time, ~20 seconds)..."
            Invoke-RestMethod https://astral.sh/uv/install.ps1 | Invoke-Expression
            $env:Path = "$UserBin;$env:Path"
            if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
                throw "uv installed but isn't on PATH yet. Close this window, open a new one, and run the installer again."
            }
            Write-Ok "uv installed"
        }
    }
    else {
        Write-Ok "Found uv"
    }

    Push-Location $RepoDir
    try {
        Write-Step "Installing dependencies (first run downloads Python, be patient)..."
        & uv sync | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Dependency install failed." }
        Write-Ok "Dependencies ready"

        # --- 2. try the person's own login first, but never dead-end on it ---
        if (Test-EnvFlag '^ODOO_PREFER_PERSONAL=(1|true|yes|on)\s*$') {
            $env:ODOO_FALLBACK_OK = "1"
            try {
                & (Get-PowerShellExe) -NoProfile -ExecutionPolicy Bypass `
                    -File (Join-Path $RepoDir "install-personal.ps1")
                $PersonalRc = $LASTEXITCODE
            }
            finally {
                $env:ODOO_FALLBACK_OK = $null
            }
            if ($PersonalRc -eq 0) { exit 0 }
            if ($PersonalRc -ne 2) { exit $PersonalRc }
            Write-Host ""
            Write-Step "Setting up with the shared company account instead..."
            Write-Host ""
        }

        # --- 3. prove the credentials work BEFORE touching Claude's config ---
        Write-Step "Testing the Odoo connection..."
        & uv run python test_connection.py
        if ($LASTEXITCODE -ne 0) {
            throw "Could not connect to Odoo. The access key may have been rotated - ask Christian for an updated link."
        }

        # --- 4. register the connector ---
        Write-Step "Setting up Claude Desktop..."
        & uv run python setup_claude.py
        if ($LASTEXITCODE -ne 0) { throw "Could not update the Claude Desktop config." }

        # --- 5. launch it the way Claude Desktop will, so failures surface here ---
        Write-Step "Checking Claude Desktop can start it..."
        & uv run python verify_connector.py
        if ($LASTEXITCODE -ne 0) {
            throw "The connector was registered but wouldn't start. Send Christian a photo of this window."
        }
    }
    finally {
        Pop-Location
    }

    # Cosmetic check only - never let it fail an install that already succeeded.
    function Test-SubPath($base, $leaf) {
        if ([string]::IsNullOrEmpty($base)) { return $false }
        try { return Test-Path (Join-Path $base $leaf) } catch { return $false }
    }
    $ClaudeInstalled = (Test-SubPath $env:LOCALAPPDATA "AnthropicClaude") -or
                       (Test-SubPath $env:PROGRAMFILES "Claude") -or
                       (Test-SubPath $env:APPDATA "Claude")

    Write-Host ""
    Write-Ok "All set."
    Write-Host ""
    if (-not $ClaudeInstalled) {
        Write-Host "NOTE: Claude Desktop doesn't look installed yet." -ForegroundColor Yellow
        Write-Host "      Install it from https://claude.ai/download, then this connector will be waiting." -ForegroundColor Yellow
        Write-Host ""
    }
    Write-Host "Next steps:" -ForegroundColor White
    Write-Host "  1. Fully quit Claude Desktop (right-click the taskbar icon -> Quit)."
    Write-Host "  2. Open it again."
    Write-Host "  3. Ask Claude:  How many leave days do I have?"
    Write-Host ""
    if (Test-EnvFlag '^ODOO_ENABLE_WRITES=(1|true|yes|on)\s*$') {
        Write-Host "WRITES ARE ENABLED - Claude can create and change real Odoo records." -ForegroundColor Yellow
    }
    else {
        Write-Host "Claude can read Odoo but not change anything." -ForegroundColor DarkGray
    }
}
catch {
    Write-Host ""
    Write-Bad $_.Exception.Message
    Write-Host ""
    Write-Host "Nothing was broken - you can just close this window." -ForegroundColor DarkGray
    Write-Host "If you're stuck, send Christian a photo of this window." -ForegroundColor DarkGray
    Write-Host ""
    if ($env:ODOO_MCP_NOPAUSE -ne "1") { Read-Host "Press Enter to close" | Out-Null }
    exit 1
}

Write-Host ""
if ($env:ODOO_MCP_NOPAUSE -ne "1") { Read-Host "Press Enter to close" | Out-Null }
