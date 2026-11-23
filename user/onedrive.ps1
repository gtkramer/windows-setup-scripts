#Requires -Version 5.1
# Uninstall the OneDrive client with its own uninstaller. OneDrive installs per user, so this
# runs as you; system\registry.psd1 blocks it by policy so it does not return.
. (Join-Path $PSScriptRoot '..\common.ps1')

Assert-NotAdmin

if (-not (Test-Path (Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\OneDrive.exe'))) {
    Write-Info 'OneDrive is not installed for this account.'
    return
}
$setup = @("$env:SystemRoot\System32\OneDriveSetup.exe", "$env:SystemRoot\SysWOW64\OneDriveSetup.exe") |
    Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $setup) {
    Write-Warn 'OneDriveSetup.exe not found; uninstall OneDrive from Settings > Apps.'
    return
}
Stop-Process -Name OneDrive -Force -ErrorAction SilentlyContinue
Start-Process -FilePath $setup -ArgumentList '/uninstall' -Wait
Write-Info 'OneDrive uninstalled for this account.'
