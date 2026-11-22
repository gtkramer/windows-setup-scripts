#Requires -Version 5.1
# STANDALONE / OPTIONAL: install Emby Server from the vendor (it is in neither the Microsoft
# Store nor winget), then open its port to the trusted LAN only. Not run by Install.ps1.
# Emby Server installs per user and updates itself, so the install runs as you; only the
# firewall rule is elevated.
. (Join-Path $PSScriptRoot '..\common.ps1')

Assert-NotAdmin

# Vendor downloads are hash-pinned: download the current Windows installer from
# https://emby.media/download.html into redist\, Get-FileHash it, then paste the SHA256 and the
# exact URL below and re-run.
$url = '<EMBY_INSTALLER_URL>'
$sha = '<EMBY_SHA256>'
if ($sha -like '<*>' -or $url -like '<*>') {
    Write-Warn 'Pin the Emby Server installer URL and SHA256 in user\emby.ps1 before use. Skipping.'
    return
}

if (Test-Path (Join-Path $env:APPDATA 'Emby-Server\system\EmbyServer.exe')) {
    Write-Info 'Emby Server already installed.'
} else {
    $inst = Get-Redist $url (Join-Path $KitRoot 'redist\emby-server.exe') $sha
    Write-Info 'Installing Emby Server (silent)...'
    Start-Process -FilePath $inst -ArgumentList '/S' -Wait
}

$code = Invoke-Elevated -ScriptPath (Join-Path $KitRoot 'system\emby-firewall.ps1')
if ($code -ne 0) { Write-Warn "The firewall rule was not added (exit $code)." }
