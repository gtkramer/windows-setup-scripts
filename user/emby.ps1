#Requires -Version 5.1
# STANDALONE / OPTIONAL: install Emby Server from the vendor (it is in neither the Microsoft
# Store nor winget), then open its port to the trusted LAN only. Not run by Install.ps1.
# Emby Server installs per user and updates itself, so the install runs as you; only the
# firewall rule is elevated.
. (Join-Path $PSScriptRoot '..\common.ps1')

Assert-NotAdmin

# The link behind "Download" on https://emby.media/windows-server.html. The release number in
# it changes with major versions; update it from that page if the download fails.
$url = 'https://embydata.com/downloads/server/release14/setup.exe'

if (Test-Path (Join-Path $env:APPDATA 'Emby-Server\system\EmbyServer.exe')) {
    Write-Info 'Emby Server already installed.'
} else {
    $inst = Save-Installer $url
    try {
        Write-Info 'Starting the Emby Server installer. Follow its window.'
        Start-Process -FilePath $inst -Wait
    } finally {
        Remove-Item $inst -Force -ErrorAction SilentlyContinue
    }
}

$code = Invoke-Elevated -ScriptPath (Join-Path $KitRoot 'system\emby-firewall.ps1')
if ($code -ne 0) { Write-Warn "The firewall rule was not added (exit $code)." }
