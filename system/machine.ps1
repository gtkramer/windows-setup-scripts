#Requires -Version 5.1
# Machine-wide settings that do not belong in the answer file: the computer name and time zone
# from common.ps1, the hardware clock, 8.3 short names, and Developer Mode.
. (Join-Path $PSScriptRoot '..\common.ps1')

Assert-Admin

# --- Computer name (takes effect after a restart) ---
if ($HostName -notmatch '^(?!\d+$)[A-Za-z0-9-]{1,15}$') { Die "HostName '$HostName' must be 1-15 letters, digits or hyphens." }
$pendingName = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' 'ComputerName'
if ($pendingName -ne $HostName) {
    Rename-Computer -NewName $HostName -Force -WarningAction SilentlyContinue
    Write-Info "Computer name set to $HostName (after the next restart)."
}

# --- Time zone ---
if ((Get-TimeZone).Id -ne $TimeZoneId) {
    Set-TimeZone -Id $TimeZoneId
    Write-Info "Time zone set to $TimeZoneId."
}

# --- Hardware clock in UTC, as Linux keeps it (read at the next restart) ---
Set-RegistryValue 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation' 'RealTimeIsUniversal' 1

# --- No 8.3 short names for new files. Existing short names are left in place. ---
fsutil behavior set disable8dot3 1 | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Warn "fsutil could not turn off 8.3 name creation (exit $LASTEXITCODE)." }

# --- Developer Mode: a non-elevated process may create symbolic links (git needs this) ---
Set-RegistryValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' 'AllowDevelopmentWithoutDevLicense' 1

Write-Info 'Machine settings applied (name, time zone, UTC clock, no new 8.3 names, Developer Mode).'
