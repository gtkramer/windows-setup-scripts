#Requires -Version 5.1
<#
.SYNOPSIS
  Upgrade the apps winget is responsible for. Run it from a normal (not elevated) terminal; it
  elevates only when a machine-wide app has an update.
.DESCRIPTION
  Windows Update, Defender signatures and Store apps update themselves and are not touched.
  Apps installed from the Store with their vendor's installer update themselves too.
  To re-apply policies and the debloat tool, re-run Install.ps1.
#>
param([switch]$Force)   # -Force: run the elevated half even when nothing looks out of date
. (Join-Path $PSScriptRoot 'common.ps1')

Assert-NotAdmin
Clear-KitWarning
Assert-Winget
$apps = Get-AppList

Write-Info '== Per-user apps =='
winget source update --disable-interactivity | Out-Null
Update-WingetPackage -Id $apps.WingetUser -Scope user

Write-Info '== Machine-wide apps =='
$pending = @($apps.WingetMachine | Where-Object { Test-WingetUpgrade $_ })
if ($pending.Count -gt 0 -or $Force) {
    if ($pending.Count -gt 0) { Write-Info "Updates available: $($pending -join ', ')" }
    $code = Invoke-Elevated -ScriptPath (Join-Path $KitRoot 'system\Update.ps1')
    if ($code -ne 0) { Write-Warn "The elevated part exited with $code." }
} else {
    Write-Info 'Nothing to upgrade; no elevation needed.'
}

Write-Info '== Status =='
$rebootKeys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
)
if ($rebootKeys | Where-Object { Test-Path $_ }) {
    Write-Warn 'A restart is pending. Restart within 2 days of the update or Windows does it for you; either way you will be asked for the BitLocker PIN.'
} else {
    Write-Info 'No restart pending.'
}
$gpu = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'NVIDIA' }
if ($gpu) { Write-Info "NVIDIA driver: $($gpu.DriverVersion) ($($gpu.Name)). Update it in the NVIDIA App." }
Show-KitWarning
