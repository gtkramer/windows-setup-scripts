#Requires -Version 5.1
<#
.SYNOPSIS
  Bring this PC to the state the kit describes. Run it as your standard account; it elevates
  once for the machine-wide part. Safe to re-run at any time (for example after the yearly
  Windows release) to re-apply policies and the debloat tool.
.DESCRIPTION
  1) system\Install.ps1  elevated: policies, hardening, debloat, Defender, machine-wide apps
  2) user\Install.ps1    as you:   Store and per-user apps, app configuration
#>
. (Join-Path $PSScriptRoot 'common.ps1')

Assert-NotAdmin

$code = Invoke-Elevated -ScriptPath (Join-Path $KitRoot 'system\Install.ps1')
if ($code -ne 0) { Die "The elevated part failed (exit $code). See the log above; fix and re-run." }

& (Join-Path $KitRoot 'user\Install.ps1')

# The answer file on the install stick holds the account passwords in reversible form.
$stickAnswerFile = Join-Path ([IO.Path]::GetPathRoot($KitRoot)) 'autounattend.xml'
if ((Test-Path $stickAnswerFile) -and ([IO.Path]::GetPathRoot($KitRoot) -ne "$SystemDrive\")) {
    Remove-Item $stickAnswerFile -Force
    Write-Info "Removed $stickAnswerFile (it held the account passwords)."
}

Write-Info 'Install complete. Sign out and back in so the shell settings take effect.'
Write-Info 'Next (see README): NVIDIA App -> security\Enable-BitLocker.ps1 -> Edge settings -> restore files.'
