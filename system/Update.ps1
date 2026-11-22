#Requires -Version 5.1
# Elevated half of Update.ps1. Launched by it through Invoke-Elevated; not run by hand.
param([string]$TargetUser, [string]$TargetSid, [string]$LogPath)
. (Join-Path $PSScriptRoot '..\common.ps1')

$code = 0
try {
    Enter-Elevated -TargetUser $TargetUser -TargetSid $TargetSid -LogPath $LogPath
    Assert-Winget
    Update-WingetPackage -Id (Get-AppList).WingetMachine -Scope machine
    Write-Info 'Machine-wide apps are up to date.'
} catch {
    Write-Warn "Update failed: $($_.Exception.Message)"
    $code = 1
}
Exit-Elevated -Code $code
