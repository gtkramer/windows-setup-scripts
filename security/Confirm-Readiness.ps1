#Requires -Version 5.1
<#
.SYNOPSIS
  Read-only report on the state the kit is meant to produce: boot security, encryption,
  accounts, policies and file-system settings. Run it from a normal terminal; it elevates
  itself (several checks need administrator rights). Changes nothing; safe to re-run.
#>
param([string]$TargetUser)
. (Join-Path $PSScriptRoot '..\common.ps1')

if (-not (Test-Admin)) { exit (Invoke-Elevated -ScriptPath $PSCommandPath) }

$rows = New-Object System.Collections.Generic.List[object]
function Add-Row {
    param([string]$Check, [string]$Value, [bool]$Pass)
    $rows.Add([pscustomobject]@{ Check = $Check; Value = $Value; Pass = $Pass })
}

$code = 0
try {
    Enter-Elevated -TargetUser $TargetUser

    # --- Boot security ---
    try { $sb = [bool](Confirm-SecureBootUEFI) } catch { $sb = $false }
    Add-Row 'Secure Boot' "$sb" $sb
    $tpm = Get-Tpm
    $tpmCim = Get-CimInstance -Namespace 'root/cimv2/security/microsofttpm' -ClassName Win32_Tpm -ErrorAction SilentlyContinue
    $tpmSpec = if ($tpmCim) { $tpmCim.SpecVersion } else { $null }
    $tpm2 = "$tpmSpec" -match '2\.0'
    Add-Row 'TPM present and ready' "present=$($tpm.TpmPresent) ready=$($tpm.TpmReady)" ([bool]$tpm.TpmPresent -and [bool]$tpm.TpmReady)
    Add-Row 'TPM 2.0' "$tpmSpec" $tpm2

    # --- Encryption ---
    try {
        $blv = Get-BitLockerVolume -MountPoint $SystemDrive
        $prot = @($blv.KeyProtector | ForEach-Object { "$($_.KeyProtectorType)" })
        $ok = ($blv.ProtectionStatus -eq 'On') -and ("$($blv.EncryptionMethod)" -eq 'XtsAes256') -and ($prot -contains 'TpmPin')
        Add-Row "BitLocker $SystemDrive (XTS-AES-256, TPM+PIN)" "$($blv.ProtectionStatus) $($blv.EncryptionMethod) [$($prot -join ',')]" $ok
    } catch {
        Add-Row "BitLocker $SystemDrive" "error: $($_.Exception.Message)" $false
    }

    # --- Accounts ---
    $aam = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'TypeOfAdminApprovalMode'
    Add-Row 'Administrator protection on' "TypeOfAdminApprovalMode=$aam" ($aam -eq 2)
    $builtin = Get-LocalUser | Where-Object { "$($_.SID)" -like 'S-1-5-21-*-500' }
    Add-Row 'Built-in Administrator disabled' "enabled=$($builtin.Enabled)" (-not $builtin.Enabled)

    # --- Policies ---
    $tel = Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry'
    Add-Row 'Diagnostic data = Required (1)' "AllowTelemetry=$tel" ($tel -eq 1)
    $noReboot = Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'NoAutoRebootWithLoggedOnUsers'
    Add-Row 'Update restart needs your say-so' "NoAutoRebootWithLoggedOnUsers=$noReboot" ($noReboot -eq 1)

    # --- Defender and firewall ---
    try {
        $mp = Get-MpComputerStatus
        Add-Row 'Defender real-time protection' "$($mp.RealTimeProtectionEnabled)" ([bool]$mp.RealTimeProtectionEnabled)
    } catch { Add-Row 'Defender real-time protection' "error: $($_.Exception.Message)" $false }
    $fw = Get-NetFirewallProfile
    $fwOk = -not ($fw | Where-Object { -not $_.Enabled -or "$($_.DefaultInboundAction)" -eq 'Allow' })
    Add-Row 'Firewall on, inbound blocked by default' (($fw | ForEach-Object { "$($_.Name)=$($_.Enabled)/$($_.DefaultInboundAction)" }) -join ' ') ([bool]$fwOk)

    # --- Machine settings (system\machine.ps1 and the answer file) ---
    Add-Row 'Computer name' "$env:COMPUTERNAME (want $HostName)" ($env:COMPUTERNAME -eq $HostName)
    $tz = (Get-TimeZone).Id
    Add-Row 'Time zone' "$tz" ($tz -eq $TimeZoneId)
    $fs = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'
    $n83 = Get-RegValue $fs 'NtfsDisable8dot3NameCreation'
    Add-Row '8.3 names off for new files' "NtfsDisable8dot3NameCreation=$n83" ($n83 -eq 1)
    $lp = Get-RegValue $fs 'LongPathsEnabled'
    Add-Row 'Long paths enabled' "LongPathsEnabled=$lp" ($lp -eq 1)
    $hb = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled'
    Add-Row 'Fast Startup off' "HiberbootEnabled=$hb" ($hb -eq 0)
    $utc = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation' 'RealTimeIsUniversal'
    Add-Row 'Hardware clock in UTC' "RealTimeIsUniversal=$utc" ($utc -eq 1)

    # --- Anti-cheat precondition ---
    Add-Row 'Anti-cheat ready (Secure Boot + TPM 2.0)' "secureboot=$sb tpm2=$tpm2" ($sb -and $tpm2)

    $rows | Format-Table Check,
        @{ Label = 'Status'; Expression = { if ($_.Pass) { 'PASS' } else { 'CHECK' } } },
        Value -AutoSize -Wrap | Out-String -Width 200 | Write-Host

    if ($rows | Where-Object { -not $_.Pass }) { Write-Warn 'One or more checks need attention (CHECK).' }
    else { Write-Info 'All checks PASS.' }
    Write-Info 'Verify by hand: HDR and VRR in Settings > Display; the BitLocker PIN prompt at the next restart.'
} catch {
    Write-Warn "Readiness check failed: $($_.Exception.Message)"
    $code = 1
}
Exit-Elevated -Code $code
