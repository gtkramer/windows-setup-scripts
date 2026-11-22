#Requires -Version 5.1
# Four settings taken from Microsoft's Windows 11 security baseline: the ones that are safe on
# an unmanaged home PC and are not already the Windows default. The baseline as a whole is NOT
# applied - it disables the Xbox services and sleep, and blocks unsigned local builds.
# All four are reversible.
. (Join-Path $PSScriptRoot '..\common.ps1')

Assert-Admin

# 1) Legacy LLMNR name lookups off (spoofable on untrusted networks). mDNS stays on.
Set-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' 'EnableMulticast' 0

# 2) AutoPlay / AutoRun off for all drive types.
$explorer = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
Set-RegistryValue $explorer 'NoDriveTypeAutoRun' 255
Set-RegistryValue $explorer 'NoAutorun' 1

# 3) No anonymous enumeration of accounts and shares.
Set-RegistryValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' 'RestrictAnonymous' 1

# 4) Remote Assistance invitations off.
Set-RegistryValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance' 'fAllowToGetHelp' 0

Write-Info 'Hardening applied.'
