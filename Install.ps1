#Requires -Version 5.1
<#
.SYNOPSIS
  Bring this PC to the state the kit describes. Run it from a normal (not elevated) terminal;
  it elevates once for the machine-wide part. Safe to re-run at any time (for example after
  the yearly Windows release) to re-apply policies and the debloat tool.
.DESCRIPTION
  1) system\Install.ps1  elevated: machine settings, policies, debloat, Defender, machine-wide apps
  2) user\Install.ps1    as you:   Store and per-user apps, app configuration
#>
. (Join-Path $PSScriptRoot 'common.ps1')

Assert-NotAdmin
Clear-KitWarning

$code = Invoke-Elevated -ScriptPath (Join-Path $KitRoot 'system\Install.ps1')
if ($code -ne 0) { Die "The elevated part failed (exit $code). Read its window, fix and re-run." }

& (Join-Path $KitRoot 'user\Install.ps1')   # repeats its own warnings at its end

Write-Info 'Install complete. Restart: the computer name, Administrator protection and the shell settings need it.'
Write-Info 'Next (see README): Windows Hello PIN -> NVIDIA App -> security\Enable-BitLocker.ps1 -> Edge settings -> restore files.'
