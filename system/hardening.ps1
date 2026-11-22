#Requires -Version 5.1
# Five settings taken from Microsoft's Windows 11 security baseline: the ones that are safe on
# an unmanaged home PC and are not already the Windows default. The baseline as a whole is NOT
# applied - it disables the Xbox services and sleep, and blocks unsigned local builds.
# All five are reversible.
. (Join-Path $PSScriptRoot '..\common.ps1')

Assert-Admin

# 1) Legacy LLMNR name lookups off (spoofable on untrusted networks). mDNS stays on.
$dns = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'
Set-RegistryValue $dns 'EnableMulticast' 0

# 2) NetBIOS name lookups off, on every network (same spoofing as LLMNR; the baseline turns
#    them off on public networks only). This is name resolution: adapters still list
#    "NetBIOS over Tcpip" as enabled, which is a separate per-adapter setting left alone.
Set-RegistryValue $dns 'EnableNetbios' 0

# 3) AutoPlay / AutoRun off for all drive types.
$explorer = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
Set-RegistryValue $explorer 'NoDriveTypeAutoRun' 255
Set-RegistryValue $explorer 'NoAutorun' 1

# 4) No anonymous enumeration of accounts and shares.
Set-RegistryValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' 'RestrictAnonymous' 1

# 5) Remote Assistance invitations off.
Set-RegistryValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance' 'fAllowToGetHelp' 0

Write-Info 'Hardening applied.'
