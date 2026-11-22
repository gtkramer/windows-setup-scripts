#Requires -Version 5.1
# Block OneDrive by policy. OneDrive installs per user, so the uninstall itself is done by the
# user half (user\onedrive.ps1); this keeps it from syncing or coming back.
. (Join-Path $PSScriptRoot '..\common.ps1')

Assert-Admin

Set-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' 'DisableFileSyncNGSC' 1

Write-Info 'OneDrive blocked by policy.'
