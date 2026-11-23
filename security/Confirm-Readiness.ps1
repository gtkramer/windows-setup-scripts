#Requires -Version 5.1
<#
.SYNOPSIS
  Read-only report on the state the kit is meant to produce: every setting the kit applies,
  and the Windows defaults it relies on without setting them. Run it from a normal terminal;
  it elevates itself (several checks need administrator rights). Changes nothing; safe to re-run.
.DESCRIPTION
  PASS means the value is what the kit wants. CHECK means look at it: something was not
  applied, was changed since, or cannot be confirmed yet (for example before the restart
  that Install.ps1 asks for, or before Enable-BitLocker.ps1 has been run).
  Registry values are read from system\registry.psd1, the same table Install.ps1 writes from,
  so a new value there is reported with no change here. A check that is not a registry value
  is written out in this script.
#>
param([string]$TargetUser)
. (Join-Path $PSScriptRoot '..\common.ps1')
. (Join-Path $PSScriptRoot 'bitlocker.ps1')

if (-not (Test-Admin)) { exit (Invoke-Elevated -ScriptPath $PSCommandPath) }

$rows = New-Object System.Collections.Generic.List[object]
function Add-Row {
    param([string]$Area, [string]$Check, [string]$Value, [bool]$Pass)
    $rows.Add([pscustomobject]@{ Area = $Area; Check = $Check; Value = $Value; Pass = $Pass })
}
function Add-Check {
    # Runs $Test, which returns @{ Value = '...'; Pass = $true/$false }. A test that throws
    # becomes a CHECK row, so one failing probe does not hide the rest of the report.
    param([string]$Area, [string]$Check, [scriptblock]$Test)
    try {
        $result = & $Test
        Add-Row $Area $Check "$($result.Value)" ([bool]$result.Pass)
    } catch {
        Add-Row $Area $Check "error: $($_.Exception.Message)" $false
    }
}

$code = 0
try {
    Enter-Elevated -TargetUser $TargetUser

    # --- Boot security ---
    try { $sb = [bool](Confirm-SecureBootUEFI) } catch { $sb = $false }
    Add-Row 'Boot' 'Secure Boot' "$sb" $sb
    Add-Check 'Boot' 'TPM present and ready' {
        $tpm = Get-Tpm
        @{ Value = "present=$($tpm.TpmPresent) ready=$($tpm.TpmReady)"; Pass = ([bool]$tpm.TpmPresent -and [bool]$tpm.TpmReady) }
    }
    $tpmCim  = Get-CimInstance -Namespace 'root/cimv2/security/microsofttpm' -ClassName Win32_Tpm -ErrorAction SilentlyContinue
    $tpmSpec = if ($tpmCim) { "$($tpmCim.SpecVersion)" } else { '' }
    $tpm2    = $tpmSpec -match '2\.0'
    Add-Row 'Boot' 'TPM 2.0' $tpmSpec $tpm2
    Add-Check 'Boot' 'Secure Boot has the 2023 Windows certificate' {
        # The 2011 certificates expired in 2026; boot-component fixes need the 2023 one.
        $db = [Text.Encoding]::ASCII.GetString((Get-SecureBootUEFI -Name db -ErrorAction Stop).Bytes)
        $servicing = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\Servicing' 'UEFICA2023Status'
        $has = $db -match 'Windows UEFI CA 2023'
        @{ Value = "in firmware=$has, Windows servicing status=$servicing"; Pass = $has }
    }

    # --- Encryption: the system drive, then every internal data drive that is connected ---
    Add-Check 'Encryption' "BitLocker $SystemDrive (XTS-AES-256, TPM+PIN)" {
        $blv  = Get-BitLockerVolume -MountPoint $SystemDrive -ErrorAction Stop
        $prot = Get-ProtectorType $blv
        @{ Value = "$($blv.ProtectionStatus) $($blv.EncryptionMethod) [$($prot -join ',')]"
           Pass  = ("$($blv.ProtectionStatus)" -eq 'On') -and ("$($blv.EncryptionMethod)" -eq 'XtsAes256') -and ($prot -contains 'TpmPin') }
    }
    try {
        $dataVolumes = @(Get-CimInstance -Namespace 'root/cimv2/Security/MicrosoftVolumeEncryption' `
                             -ClassName Win32_EncryptableVolume -ErrorAction Stop |
                         Where-Object { $_.VolumeType -eq 1 -and $_.DriveLetter })   # 1 = fixed data
    } catch {
        $dataVolumes = @()
        Add-Row 'Encryption' 'Internal data drives' "error: $($_.Exception.Message)" $false
    }
    foreach ($dataVolume in $dataVolumes) {
        $letter = $dataVolume.DriveLetter
        Add-Check 'Encryption' "BitLocker $letter (XTS-AES-256, unlocks automatically)" {
            $v = Get-BitLockerVolume -MountPoint $letter -ErrorAction Stop
            if ("$($v.LockStatus)" -eq 'Locked') {
                return @{ Value = 'Locked: run security\Enable-BitLockerDataDrive.ps1 with its recovery key'; Pass = $false }
            }
            @{ Value = "$($v.VolumeStatus) $($v.EncryptionPercentage)% $($v.ProtectionStatus) $($v.EncryptionMethod) auto-unlock=$($v.AutoUnlockEnabled)"
               Pass  = ("$($v.VolumeStatus)" -eq 'FullyEncrypted') -and ("$($v.ProtectionStatus)" -eq 'On') -and
                       ("$($v.EncryptionMethod)" -eq 'XtsAes256') -and ($v.AutoUnlockEnabled -eq $true) }
        }
    }

    # --- Accounts ---
    Add-Check 'Accounts' 'Administrator protection in effect' {
        # Not just configured: the elevated window must run as a different account than yours.
        $state = Get-AdminProtectionState -TargetUser $TargetUser
        $note  = switch ($state) {
            'On'      { 'separate elevated account' }
            'Pending' { 'configured, but elevated as your own account: restart, or this build does not apply it' }
            'Off'     { 'not configured' }
            default   { "could not look up $TargetUser as a local account" }
        }
        @{ Value = "$state - you are $TargetUser, this window is $env:USERNAME ($note)"; Pass = ($state -eq 'On') }
    }
    Add-Check 'Accounts' 'Built-in Administrator disabled' {
        $builtin = Get-LocalUser | Where-Object { "$($_.SID)" -like 'S-1-5-21-*-500' }
        @{ Value = "enabled=$($builtin.Enabled)"; Pass = (-not $builtin.Enabled) }
    }

    # --- Every registry value in system\registry.psd1: what Install.ps1 and the BitLocker
    #     scripts write, and what the kit relies on. A wanted value of $null must be absent. ---
    foreach ($e in @(Get-KitRegistry)) {
        $have  = Get-RegValue $e.Path $e.Name
        $shown = if ($null -eq $have) { '(absent)' } else { "$have" }
        $pass  = if ($null -eq $e.Value) { $null -eq $have } else { ($null -ne $have) -and ("$have" -eq "$($e.Value)") }
        Add-Row $e.Area $e.Check "$($e.Name)=$shown" $pass
    }
    Add-Check 'Updates' 'Updates for other Microsoft products in effect' {
        # Not just configured: Windows Update must list the Microsoft Update service as one it
        # scans automatically. It registers the service at the first update check after the
        # policy is set.
        $services = (New-Object -ComObject Microsoft.Update.ServiceManager).Services
        $mu = $services | Where-Object { "$($_.ServiceID)" -eq '7971f918-a847-4430-9279-4a52d1efe18d' } | Select-Object -First 1
        if (-not $mu) { return @{ Value = 'Microsoft Update is not registered yet: check for updates once, then re-run'; Pass = $false } }
        @{ Value = "Microsoft Update registered, scanned automatically=$($mu.IsRegisteredWithAU)"; Pass = [bool]$mu.IsRegisteredWithAU }
    }
    Add-Check 'Answer file' 'PowerShell scripts allowed (RemoteSigned)' {
        $policy = Get-ExecutionPolicy -Scope LocalMachine
        @{ Value = "$policy"; Pass = ("$policy" -eq 'RemoteSigned') }
    }
    Add-Check 'Answer file' "$SystemDrive\ not writable by standard users" {
        # The answer file removes the two "Authenticated Users" entries from the drive's root,
        # so only an administrator can create a folder directly under it.
        $sid   = 'S-1-5-11'   # Authenticated Users
        $rules = (Get-Acl -LiteralPath "$SystemDrive\").GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])
        $found = @($rules | Where-Object { "$($_.IdentityReference)" -eq $sid -and "$($_.AccessControlType)" -eq 'Allow' })
        if ($found.Count -eq 0) { return @{ Value = 'no Authenticated Users entry'; Pass = $true } }
        @{ Value = "Authenticated Users: $(($found | ForEach-Object { "$($_.FileSystemRights)" }) -join '; ')"; Pass = $false }
    }
    Add-Row 'Machine' 'Computer name' "$env:COMPUTERNAME (want $HostName)" ($env:COMPUTERNAME -eq $HostName)
    $tz = (Get-TimeZone).Id
    Add-Row 'Machine' 'Time zone' "$tz" ($tz -eq $TimeZoneId)

    # --- Defender (system\defender.ps1, plus the defaults it leaves alone) ---
    Add-Check 'Defender' 'Real-time protection' {
        $mp = Get-MpComputerStatus
        @{ Value = "$($mp.RealTimeProtectionEnabled)"; Pass = [bool]$mp.RealTimeProtectionEnabled }
    }
    Add-Check 'Defender' 'Tamper protection' {
        $mp = Get-MpComputerStatus
        @{ Value = "$($mp.IsTamperProtected)"; Pass = [bool]$mp.IsTamperProtected }
    }
    Add-Check 'Defender' 'Signatures at most 3 days old' {
        $mp = Get-MpComputerStatus
        @{ Value = "$($mp.AntivirusSignatureAge) day(s)"; Pass = ($mp.AntivirusSignatureAge -le 3) }
    }
    Add-Check 'Defender' 'Cloud-delivered protection' {
        $level = (Get-MpPreference).MAPSReporting
        @{ Value = "MAPSReporting=$level"; Pass = ($level -in 1, 2) }
    }
    Add-Check 'Defender' 'Unwanted-app blocking' {
        $pua = (Get-MpPreference).PUAProtection
        @{ Value = "PUAProtection=$pua"; Pass = ($pua -eq 1) }
    }
    Add-Check 'Defender' 'Network protection' {
        $np = (Get-MpPreference).EnableNetworkProtection
        @{ Value = "EnableNetworkProtection=$np"; Pass = ($np -eq 1) }
    }
    $asrState = try { Get-AsrRuleState } catch { @{} }
    foreach ($ruleId in $AsrRules.Keys) {
        $action = if ($asrState.ContainsKey($ruleId)) { "$($asrState[$ruleId])" } else { '(not set)' }
        Add-Row 'Defender rules' $AsrRules[$ruleId] "action=$action" ($action -eq '1')
    }

    # --- Windows defaults the kit relies on and does not set ---
    $hvci = $false
    try {
        $dg   = Get-CimInstance -Namespace 'root/Microsoft/Windows/DeviceGuard' -ClassName Win32_DeviceGuard -ErrorAction Stop
        $hvci = @($dg.SecurityServicesRunning) -contains 2
        Add-Row 'Windows defaults' 'Memory integrity running' "services running=[$(@($dg.SecurityServicesRunning) -join ',')]" $hvci
    } catch {
        Add-Row 'Windows defaults' 'Memory integrity running' "error: $($_.Exception.Message)" $false
    }
    Add-Check 'Windows defaults' 'LSA protection running' {
        # Event 12 from Wininit says LSASS started as a protected process on this boot; the
        # registry values only say what is configured.
        $boot    = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
        $started = [bool](Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Wininit'; Id = 12; StartTime = $boot } `
                              -MaxEvents 1 -ErrorAction SilentlyContinue)
        $lsa     = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
        $ppl     = Get-RegValue $lsa 'RunAsPPL'
        $pplBoot = Get-RegValue $lsa 'RunAsPPLBoot'
        @{ Value = "started protected this boot=$started, RunAsPPL=$ppl, RunAsPPLBoot=$pplBoot"
           Pass  = $started -or ($pplBoot -in 1, 2) }
    }
    Add-Check 'Windows defaults' 'Vulnerable driver blocklist' {
        $bl = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Config' 'VulnerableDriverBlocklistEnable'
        $shown = if ($null -eq $bl) { '(absent: on with memory integrity)' } else { "$bl" }
        @{ Value = "VulnerableDriverBlocklistEnable=$shown"; Pass = ($bl -eq 1) -or ($null -eq $bl -and $hvci) }
    }
    Add-Check 'Windows defaults' 'SmartScreen for apps and files not turned off' {
        $shell  = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer' 'SmartScreenEnabled'
        $policy = Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'EnableSmartScreen'
        $shown  = "SmartScreenEnabled=$(if ($null -eq $shell) { '(absent: on)' } else { $shell }), policy EnableSmartScreen=$(if ($null -eq $policy) { '(absent)' } else { $policy })"
        @{ Value = $shown; Pass = ("$shell" -ne 'Off') -and ($policy -ne 0) }
    }
    Add-Check 'Windows defaults' 'Firewall on, inbound blocked by default' {
        $fw = Get-NetFirewallProfile
        $bad = $fw | Where-Object { -not $_.Enabled -or "$($_.DefaultInboundAction)" -eq 'Allow' }
        @{ Value = (($fw | ForEach-Object { "$($_.Name)=$($_.Enabled)/$($_.DefaultInboundAction)" }) -join ' '); Pass = (-not $bad) }
    }

    # --- Anti-cheat precondition ---
    Add-Row 'Games' 'Anti-cheat ready (Secure Boot + TPM 2.0)' "secureboot=$sb tpm2=$tpm2" ($sb -and $tpm2)

    # Print area by area, in this order, whatever order the checks ran in.
    $areaOrder = 'Boot', 'Encryption', 'Accounts', 'Answer file', 'Machine', 'Policy', 'Updates', 'Edge',
                 'Hardening', 'OneDrive', 'Defender', 'Defender rules', 'Windows defaults', 'Games'
    $areaOrder += @($rows | ForEach-Object { $_.Area } | Select-Object -Unique | Where-Object { $_ -notin $areaOrder })   # an area new to registry.psd1
    $ordered = foreach ($area in $areaOrder) { $rows | Where-Object { $_.Area -eq $area } }
    $ordered | Format-Table Area, Check,
        @{ Label = 'Status'; Expression = { if ($_.Pass) { 'PASS' } else { 'CHECK' } } },
        Value -AutoSize -Wrap | Out-String -Width 220 | Write-Host

    $failed = @($rows | Where-Object { -not $_.Pass })
    if ($failed.Count -gt 0) { Write-Warn "$($failed.Count) of $($rows.Count) checks need attention (CHECK)." }
    else { Write-Info "All $($rows.Count) checks PASS." }
    Write-Info 'Verify by hand, because a script cannot:'
    Write-Info '  - edge://policy in Edge: the kit''s policies are listed with status OK'
    Write-Info '  - Windows Security > App & browser control > Reputation-based protection: all on'
    Write-Info '  - an internal drive that is not connected right now (the backup drive) is not in this report'
    Write-Info '  - the BitLocker PIN prompt at the next restart; HDR and VRR in Settings > Display'
} catch {
    Write-Warn "Readiness check failed: $($_.Exception.Message)"
    $code = 1
}
Exit-Elevated -Code $code
