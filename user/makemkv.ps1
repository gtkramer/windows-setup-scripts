#Requires -Version 5.1
# Place the MakeMKV AACS KEYDB.cfg for Blu-ray decryption. On Windows, libaacs (used by
# VLC) reads %APPDATA%\aacs\KEYDB.cfg.
. (Join-Path $PSScriptRoot '..\common.ps1')

if (-not (Test-Path $KeyDbSource)) {
    Write-Warn "KEYDB.cfg not found at $KeyDbSource - skipping. Place it there and re-run to enable AACS."
    return
}
$dest = Join-Path $env:APPDATA 'aacs'
if (-not (Test-Path $dest)) { New-Item $dest -ItemType Directory -Force | Out-Null }
Copy-Item -Force $KeyDbSource (Join-Path $dest 'KEYDB.cfg')
Write-Info "AACS KEYDB.cfg installed to $dest"
