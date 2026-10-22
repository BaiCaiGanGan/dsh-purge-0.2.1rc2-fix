#Requires -Version 5.1
<#
  dsh-purge: apply + restart + verify (generic, safe to commit).

  Why this script exists: Electron loads resources\app.asar BEFORE resources\app.
  The plugin patches files under resources\app, so the sealed archive has to be
  renamed once and the host restarted before any patch is actually running.
  The plugin UI can do it too; this script does the same thing from outside the
  host (useful when the UI cannot load, or for scripted verification).

  Safety: the archive is renamed, never deleted (app.asar.bak-<timestamp>).

  Usage:
    .\apply-and-verify.ps1                    # apply + restart + verify
    .\apply-and-verify.ps1 -VerifyOnly        # verify only, no restart
    .\apply-and-verify.ps1 -InstallRoot "D:\Apps\DeepSeek Harness"
    .\apply-and-verify.ps1 -Profile web       # web/CLI profile instead of desktop

  Exit codes: 0 ok, 1 not effective / not found, 2 bad input.
#>
param(
    [string]$InstallRoot = "",
    [string]$Profile = "desktop",
    [switch]$VerifyOnly
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

function Write-Head($text) { Write-Host ""; Write-Host "== $text ==" -ForegroundColor Cyan }
function Fail($text) { Write-Host $text -ForegroundColor Red; exit 2 }

# plugin root = parent of this script directory
$plugin = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $plugin "lib\core.js"))) {
    Fail "cannot locate plugin: $plugin (run this from <plugin>/scripts/)"
}

function Resolve-Exe {
    param([string]$Hint)
    $candidates = @()
    if ($Hint) {
        if (Test-Path $Hint -PathType Leaf) { $candidates += $Hint }
        else { $candidates += (Join-Path $Hint "DeepSeek Harness.exe") }
    }
    if ($env:DSH_DESKTOP_INSTALL) {
        if (Test-Path $env:DSH_DESKTOP_INSTALL -PathType Leaf) { $candidates += $env:DSH_DESKTOP_INSTALL }
        else { $candidates += (Join-Path $env:DSH_DESKTOP_INSTALL "DeepSeek Harness.exe") }
    }
    try {
        $running = Get-Process -Name "DeepSeek Harness" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($running -and $running.Path) { $candidates += $running.Path }
    } catch { }
    $candidates += (Join-Path $env:LOCALAPPDATA "Programs\DeepSeek Harness\DeepSeek Harness.exe")
    $candidates += (Join-Path $env:ProgramFiles "DeepSeek Harness\DeepSeek Harness.exe")
    foreach ($c in $candidates) { if ($c -and (Test-Path $c)) { return $c } }
    return ""
}

$exe = Resolve-Exe -Hint $InstallRoot
if (-not $exe) { Fail "DeepSeek Harness.exe not found. Pass -InstallRoot (the folder that contains it)." }
$res = Join-Path (Split-Path -Parent $exe) "resources"
$asar = Join-Path $res "app.asar"
$appDir = Join-Path $res "app"
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$bak = "$asar.bak-$stamp"

Write-Host "dsh-purge apply/verify" -ForegroundColor Cyan
Write-Host ("host      : " + $exe)
Write-Host ("plugin    : " + $plugin)
Write-Host ("profile   : " + $Profile)

if (-not $VerifyOnly) {
    if (-not (Test-Path $appDir)) { Fail "resources\app missing - run the plugin Apply once first." }

    Write-Head "stop host"
    Get-Process -Name "DeepSeek Harness" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    for ($i = 0; $i -lt 60; $i++) {
        if (-not (Get-Process -Name "DeepSeek Harness" -ErrorAction SilentlyContinue)) { break }
        Start-Sleep -Milliseconds 500
    }
    Write-Host ("remaining host processes: " + @(Get-Process -Name "DeepSeek Harness" -ErrorAction SilentlyContinue).Count)

    Write-Head "move app.asar aside"
    if (-not (Test-Path $asar)) {
        Write-Host "app.asar already absent - nothing to move"
    } else {
        $moved = $false
        for ($i = 0; $i -lt 80; $i++) {
            try {
                if (-not (Test-Path $asar)) { $moved = $true; break }
                Move-Item -LiteralPath $asar -Destination $bak -Force
                $moved = $true
                break
            } catch { Start-Sleep -Milliseconds 300 }
        }
        if ($moved) { Write-Host ("moved -> " + $bak) -ForegroundColor Green }
        else { Write-Host "MOVE FAILED (archive still locked). Quit the tray app, then rerun." -ForegroundColor Yellow }
    }

    Write-Head "relaunch"
    Start-Process -FilePath $exe
    Write-Host "host relaunched, waiting 12s ..."
    Start-Sleep -Seconds 12
}

Write-Head "verify"
$env:DSH_SURFACE = "desktop"
$env:DSH_BASE = Join-Path $appDir "dsh\node_modules\@deepseek-ai"
$env:DSH_DESKTOP_INSTALL = $exe
if (-not $env:DSH_HOME) { $env:DSH_HOME = Join-Path $env:USERPROFILE ".dsh" }

$probe = Join-Path $env:TEMP ("dsh-purge-probe-" + $stamp + ".mjs")
$probeSrc = @"
const c = await import(process.argv[2])
const s = await c.gatherState()
console.log(JSON.stringify({applied:s.patches_applied,pending:s.patches_pending,drifted:s.patches_drifted,failed:s.patches_failed,na:s.patches_na,effective:s.effective,asar_still_sealed:s.asar_still_sealed,override:s.override_status,backup:s.has_backup}))
"@
[System.IO.File]::WriteAllText($probe, $probeSrc, (New-Object System.Text.UTF8Encoding($false)))
$coreUrl = ([uri](Join-Path $plugin "lib\core.js")).AbsoluteUri
$raw = & node $probe $coreUrl 2>&1
Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
if ($LASTEXITCODE -ne 0) { Write-Host "probe failed:" -ForegroundColor Red; Write-Host $raw; exit 1 }
$st = $raw | ConvertFrom-Json

$asarNow = Test-Path $asar
Write-Host ""
Write-Host ("  patches applied : " + $st.applied + "  (pending " + $st.pending + ", drifted " + $st.drifted + ", failed " + $st.failed + ", n/a " + $st.na + ")")
Write-Host ("  app.asar        : " + $(if ($asarNow) { "STILL PRESENT (host boots the sealed archive)" } else { "absent (host boots resources/app)" }))
Write-Host ("  override        : " + $st.override)
Write-Host ("  backup          : " + $(if ($st.backup) { "yes" } else { "no" }))
Write-Host ""
if ($st.effective -eq $true -and -not $asarNow -and $st.drifted -eq 0) {
    Write-Host "  EFFECTIVE = YES  - patched bundle is what the host is running." -ForegroundColor Green
    exit 0
}
Write-Host "  EFFECTIVE = NO   - see the lines above." -ForegroundColor Yellow
if ($asarNow) { Write-Host "  -> quit the tray app completely, then rerun without -VerifyOnly." -ForegroundColor Yellow }
if ($st.drifted -gt 0) { Write-Host "  -> drifted patches: the host moved, anchors need updating." -ForegroundColor Yellow }
exit 1