#Requires -Version 5.1
# Accommodations so a standard user can develop without elevating for everyday things.
. (Join-Path $PSScriptRoot '..\common.ps1')

Assert-Admin

$targetUser = Get-Variable -Name KitTargetUser -Scope Global -ValueOnly -ErrorAction SilentlyContinue
if (-not $targetUser) { Die 'No target user: this module runs only from an elevated kit script.' }

# Hyper-V Administrators (well-known group S-1-5-32-578): manage VMs without elevation.
$hyperVAdmins = Get-LocalGroup -SID 'S-1-5-32-578' -ErrorAction SilentlyContinue
if ($hyperVAdmins) {
    $isMember = Get-LocalGroupMember -Group $hyperVAdmins -ErrorAction SilentlyContinue |
        Where-Object { ($_.Name -split '\\')[-1] -eq $targetUser }
    if (-not $isMember) {
        Add-LocalGroupMember -Group $hyperVAdmins -Member $targetUser
        Write-Info "$targetUser added to $($hyperVAdmins.Name) (sign out and in to take effect)."
    }
} else {
    Write-Info 'Hyper-V Administrators group not present; skipped.'
}

# Developer Mode: symbolic links without elevation, among other things.
Set-RegistryValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' 'AllowDevelopmentWithoutDevLicense' 1

Write-Info 'Developer accommodations applied.'
