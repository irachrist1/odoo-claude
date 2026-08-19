# One-command install. The user runs a single line in PowerShell; this downloads the
# connector and runs the installer. No git, no admin rights, no unzipping by hand.
#
#   irm https://raw.githubusercontent.com/irachrist1/odoo-claude/main/bootstrap.ps1 | iex
#
$ZipUrl  = if ($env:ODOO_MCP_ZIP) { $env:ODOO_MCP_ZIP } else { "https://codeload.github.com/irachrist1/odoo-claude/zip/refs/heads/main" }
$Dest    = Join-Path $env:LOCALAPPDATA "OdooClaude"

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Host ""
Write-Host "===  Odoo in Claude - installer  ===" -ForegroundColor White
Write-Host ""

try {
    # Checked by shape, not by comparing against the placeholder text: the placeholder
    # also appears in the assignment above, so a find-and-replace of it would rewrite
    # both spots and make a sentinel comparison match forever.
    if ($ZipUrl -notmatch '^https?://') {
        throw "This installer link hasn't been configured yet. Ask Christian for the correct command."
    }

    $Tmp = Join-Path $env:TEMP ("odoo-claude-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $Tmp -Force | Out-Null
    $Zip = Join-Path $Tmp "bundle.zip"

    Write-Host "-> Downloading..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $ZipUrl -OutFile $Zip -UseBasicParsing

    Write-Host "-> Unpacking..." -ForegroundColor Cyan
    $Unpacked = Join-Path $Tmp "x"
    Expand-Archive -Path $Zip -DestinationPath $Unpacked -Force

    # Archive hosts wrap everything in a single top-level folder; step into it.
    $Root = $Unpacked
    $Entries = @(Get-ChildItem -Path $Unpacked)
    if ($Entries.Count -eq 1 -and $Entries[0].PSIsContainer) { $Root = $Entries[0].FullName }

    if (-not (Test-Path (Join-Path $Root "install.ps1"))) {
        throw "The downloaded file doesn't look like the Odoo connector. Ask Christian to check the install link."
    }

    Write-Host "-> Installing to $Dest" -ForegroundColor Cyan
    if (Test-Path $Dest) { Remove-Item $Dest -Recurse -Force }
    New-Item -ItemType Directory -Path $Dest -Force | Out-Null
    Copy-Item -Path (Join-Path $Root "*") -Destination $Dest -Recurse -Force

    Remove-Item $Tmp -Recurse -Force -ErrorAction SilentlyContinue

    # Anything extracted from a downloaded zip carries Mark-of-the-Web, which blocks
    # it even under RemoteSigned. Strip that before trying to run any of it.
    Get-ChildItem -Path $Dest -Recurse -Include *.ps1, *.bat -ErrorAction SilentlyContinue |
        Unblock-File -ErrorAction SilentlyContinue

    # This script arrived via 'irm | iex'. Piped text isn't subject to execution policy,
    # but the .ps1 file below is - and Windows ships Restricted by default, so running
    # it directly fails on a stock machine. Relaunch through a child shell with Bypass:
    # it's scoped to that one process, needs no admin, and changes nothing system-wide.
    $Installer = Join-Path $Dest "install.ps1"
    $PsExe = "powershell.exe"
    if (-not (Get-Command $PsExe -ErrorAction SilentlyContinue)) { $PsExe = "pwsh" }
    & $PsExe -NoProfile -ExecutionPolicy Bypass -File $Installer
}
catch {
    Write-Host ""
    Write-Host "!! $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Nothing was broken - you can just close this window." -ForegroundColor DarkGray
    Write-Host "If you're stuck, send Christian a photo of this window." -ForegroundColor DarkGray
    Write-Host ""
    exit 1
}
