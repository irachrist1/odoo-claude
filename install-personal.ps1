# Sets up the Odoo connector using the person's OWN Odoo login.
# Credentials go straight into Claude's config and are never written to disk here.
#
# ODOO_FALLBACK_OK=1 means the caller has a shared account to fall back on, so
# skipping or failing exits 2 instead of being fatal.

$ErrorActionPreference = "Stop"
$RepoDir = $PSScriptRoot
$EnvFile = Join-Path $RepoDir ".env"
$OdooUrl = "https://rw-andersen.odoo.com"
$OdooDb = "rw-andersen"
$Fallback = ($env:ODOO_FALLBACK_OK -eq "1")

function Write-Step($msg) { Write-Host "-> $msg" -ForegroundColor Cyan }

function Test-EnvFlag($pattern) {
    if (-not (Test-Path $EnvFile)) { return $false }
    return Select-String -Path $EnvFile -Pattern $pattern -Quiet
}

try {
    # When called directly (no fallback available) we own the whole install.
    if (-not $Fallback) {
        Write-Host ""
        Write-Host "===  Odoo in Claude - Maj Andersen (RW) Ltd  ===" -ForegroundColor White
        Write-Host ""

        $UserBin = Join-Path $env:USERPROFILE ".local\bin"
        if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
            if (Test-Path (Join-Path $UserBin "uv.exe")) {
                $env:Path = "$UserBin;$env:Path"
            }
            else {
                Write-Step "Installing uv (one-time, ~20 seconds)..."
                Invoke-RestMethod https://astral.sh/uv/install.ps1 | Invoke-Expression
                $env:Path = "$UserBin;$env:Path"
                if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
                    throw "uv installed but isn't on PATH yet. Close this window, open a new one, and run the installer again."
                }
            }
        }

        Push-Location $RepoDir
        Write-Step "Installing dependencies (first run downloads Python, be patient)..."
        & uv sync | Out-Null
        if ($LASTEXITCODE -ne 0) { Pop-Location; throw "Dependency install failed." }
        Pop-Location
    }

    Push-Location $RepoDir
    try {
        Write-Host ""
        Write-Host "Sign in with your own Odoo account so Claude sees your data." -ForegroundColor White
        Write-Host ""
        Write-Host "Opening Odoo in your browser. Once it loads:" -ForegroundColor White
        Write-Host "  1. Click your photo (top-right)  ->  My Profile"
        Write-Host "  2. Open the  Account Security  tab"
        Write-Host "  3. Click  New API Key , name it 'claude', and copy the key"
        Write-Host ""
        if ($env:ODOO_MCP_NO_BROWSER -eq "1") {
            Write-Host "  (Open $OdooUrl yourself)" -ForegroundColor DarkGray
        }
        else {
            try { Start-Process $OdooUrl } catch { Write-Host "  (Open $OdooUrl yourself)" -ForegroundColor DarkGray }
        }

        if ($Fallback) { $SkipHint = " (or press Enter to use the shared company account)" } else { $SkipHint = "" }

        $Ok = $false
        for ($Attempt = 1; $Attempt -le 3 -and -not $Ok; $Attempt++) {
            $Email = (Read-Host "Your Odoo email$SkipHint").Trim()

            if ([string]::IsNullOrWhiteSpace($Email) -and $Fallback) { exit 2 }

            $KeySecure = Read-Host "Paste your API key (hidden)" -AsSecureString
            $Key = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [Runtime.InteropServices.Marshal]::SecureStringToBSTR($KeySecure)).Trim()

            if ([string]::IsNullOrWhiteSpace($Email) -or [string]::IsNullOrWhiteSpace($Key)) {
                Write-Host "Both are needed - let's try again." -ForegroundColor Yellow
                Write-Host ""
                continue
            }

            # Fallbacks: a personal bundle's .env supplies these, but set them anyway
            # so this script also works standalone with no .env present at all.
            if (-not $env:ODOO_URL) { $env:ODOO_URL = $OdooUrl }
            if (-not $env:ODOO_DB) { $env:ODOO_DB = $OdooDb }
            $env:ODOO_USERNAME = $Email
            $env:ODOO_API_KEY = $Key

            Write-Host ""
            Write-Step "Checking your login..."
            & uv run python test_connection.py
            if ($LASTEXITCODE -eq 0) {
                $Ok = $true
            }
            elseif ($Attempt -lt 3) {
                Write-Host ""
                Write-Host "That didn't work. Check the email is your Odoo login and that the key was" -ForegroundColor Yellow
                Write-Host "copied completely, then try again ($(3 - $Attempt) left)." -ForegroundColor Yellow
                Write-Host ""
            }
        }

        if (-not $Ok) {
            if ($Fallback) { exit 2 }
            throw "Couldn't sign in to Odoo. Ask Christian to check your Odoo account is active."
        }

        Write-Host ""
        Write-Step "Setting up Claude Desktop..."
        & uv run python setup_claude.py
        if ($LASTEXITCODE -ne 0) { throw "Could not update the Claude Desktop config." }

        Write-Step "Checking Claude Desktop can start it..."
        & uv run python verify_connector.py
        if ($LASTEXITCODE -ne 0) { throw "The connector was registered but wouldn't start." }
    }
    finally {
        Pop-Location
        $env:ODOO_API_KEY = $null
    }

    Write-Host ""
    Write-Host "OK All set." -ForegroundColor Green
    Write-Host ""
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
    Write-Host "!! $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Nothing was broken - you can just close this window." -ForegroundColor DarkGray
    Write-Host ""
    if ($env:ODOO_MCP_NOPAUSE -ne "1") { Read-Host "Press Enter to close" | Out-Null }
    exit 1
}

Write-Host ""
if ($env:ODOO_MCP_NOPAUSE -ne "1") { Read-Host "Press Enter to close" | Out-Null }
