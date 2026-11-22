#Requires -Version 5.1
# Six settings taken from Microsoft's Windows 11 security baseline: the ones that are safe on
# an unmanaged home PC. The baseline as a whole is NOT applied - it denies elevation requests
# from standard users, disables the Xbox services and sleep, and blocks unsigned local builds.
# All six are reversible; none uses a firmware (UEFI) lock.
. (Join-Path $PSScriptRoot '..\common.ps1')

Assert-Admin

$lsa = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'

# 1) Protect the sign-in process (LSASS) against credential theft. 2 = on, without UEFI lock.
Set-RegistryValue $lsa 'RunAsPPL' 2

# 2) Legacy LLMNR name lookups off (spoofable on untrusted networks). mDNS stays on.
Set-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' 'EnableMulticast' 0

# 3) AutoPlay / AutoRun off for all drive types.
$explorer = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
Set-RegistryValue $explorer 'NoDriveTypeAutoRun' 255
Set-RegistryValue $explorer 'NoAutorun' 1

# 4) Refuse LM and NTLMv1; send NTLMv2 only.
Set-RegistryValue $lsa 'LmCompatibilityLevel' 5

# 5) No anonymous enumeration of accounts and shares.
Set-RegistryValue $lsa 'RestrictAnonymous' 1

# 6) Remote Assistance invitations off.
Set-RegistryValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance' 'fAllowToGetHelp' 0

Write-Info 'Hardening applied (sign-in protection takes effect after a restart).'
