#Requires -Version 5.1
<#
.SYNOPSIS
  Encrypt the system drive with BitLocker: XTS-AES-256, unlocked at boot by TPM plus a PIN you
  type here. The recovery key is shown once for you to save in your password manager; it is
  never written to a file and never uploaded.
.DESCRIPTION
  Run it from a normal terminal; it elevates itself. Run it once after the NVIDIA and firmware
  installs and before restoring your files. Windows then checks at the next restart that PIN
  entry works, and starts encrypting once it does.
  Acts only on a drive that is not encrypted at all; in any other state it stops and explains.
#>
param([string]$TargetUser)
. (Join-Path $PSScriptRoot '..\common.ps1')

if (-not (Test-Admin)) { exit (Invoke-Elevated -ScriptPath $PSCommandPath) }

function Read-Plain {
    # Reads a secret without echo and returns it as text for comparison.
    param([string]$Prompt)
    $secure = Read-Host $Prompt -AsSecureString
    return [Net.NetworkCredential]::new('', $secure).Password
}

$code = 0
try {
    Enter-Elevated -TargetUser $TargetUser

    # --- Preconditions: UEFI Secure Boot and a ready TPM ---
    try { $secureBoot = Confirm-SecureBootUEFI }
    catch { Die 'Not booted in UEFI mode. BitLocker with TPM and PIN needs UEFI and Secure Boot.' }
    if (-not $secureBoot) { Die 'Secure Boot is not enabled. Enable it in firmware first (see README).' }
    $tpm = Get-Tpm
    if (-not $tpm.TpmPresent -or -not $tpm.TpmReady) { Die 'The TPM is not present or not ready. Enable PTT/fTPM in firmware first.' }

    # --- Act only on a clean state ---
    $vol   = Get-BitLockerVolume -MountPoint $SystemDrive
    $types = @($vol.KeyProtector | ForEach-Object { "$($_.KeyProtectorType)" })
    if ($vol.ProtectionStatus -eq 'On' -and $types -contains 'TpmPin') {
        Write-Info "$SystemDrive is already protected ($($vol.EncryptionMethod); $($types -join ', ')). Nothing to do."
        Exit-Elevated -Code 0
    }
    if ($vol.VolumeStatus -eq 'FullyDecrypted' -and $types -contains 'TpmPin') {
        Write-Info 'BitLocker is set up and waiting for a restart to check PIN entry. Restart the PC.'
        Exit-Elevated -Code 0
    }
    $unexpected = @($types | Where-Object { $_ -ne 'RecoveryPassword' })
    if ($vol.VolumeStatus -ne 'FullyDecrypted' -or $unexpected.Count -gt 0) {
        Die @"
$SystemDrive is in a state this script does not change:
  status $($vol.VolumeStatus), protection $($vol.ProtectionStatus), method $($vol.EncryptionMethod), protectors [$($types -join ', ')]
The cipher cannot be changed on an encrypted drive. To start over, decrypt it first
(manage-bde -off $SystemDrive, wait for 'Fully Decrypted' in manage-bde -status), then re-run.
"@
    }

    # --- Policy: XTS-AES-256, and a startup PIN allowed. Must be in place before enabling. ---
    $fve = 'HKLM:\SOFTWARE\Policies\Microsoft\FVE'
    Set-RegistryValue $fve 'EncryptionMethodWithXtsOs'  7
    Set-RegistryValue $fve 'EncryptionMethodWithXtsFdv' 7
    Set-RegistryValue $fve 'EncryptionMethodWithXtsRdv' 7
    Set-RegistryValue $fve 'UseAdvancedStartup' 1
    Set-RegistryValue $fve 'EnableBDEWithNoTPM' 0
    foreach ($name in 'UseTPM', 'UseTPMPIN', 'UseTPMKey', 'UseTPMKeyPIN') { Set-RegistryValue $fve $name 2 }   # 2 = allow

    # --- The PIN: typed twice, never written anywhere ---
    while ($true) {
        $pinText = Read-Plain 'BitLocker startup PIN (6 to 20 digits)'
        if ($pinText -notmatch '^\d{6,20}$') { Write-Warn 'The PIN must be 6 to 20 digits.'; continue }
        if ($pinText -ne (Read-Plain 'Type the PIN again')) { Write-Warn 'The two entries differ.'; continue }
        break
    }
    $pin = ConvertTo-SecureString $pinText -AsPlainText -Force
    $pinText = $null

    # --- Recovery key first: shown, saved by you, and typed back before anything is encrypted ---
    # BitLocker's own warnings are silenced because they repeat the recovery key.
    if ($types -notcontains 'RecoveryPassword') {
        Add-BitLockerKeyProtector -MountPoint $SystemDrive -RecoveryPasswordProtector -WarningAction SilentlyContinue | Out-Null
    }
    $rp = (Get-BitLockerVolume -MountPoint $SystemDrive).KeyProtector |
          Where-Object KeyProtectorType -eq 'RecoveryPassword' | Select-Object -Last 1
    if (-not $rp -or -not $rp.RecoveryPassword) { Die 'The recovery key was not created; nothing was encrypted.' }

    Write-Host ''
    Write-Host "  BitLocker recovery key - $HostName - $SystemDrive - $(Get-Date -Format 'yyyy-MM-dd')"
    Write-Host "  Key ID       : $($rp.KeyProtectorId)"
    Write-Host "  Recovery key : $($rp.RecoveryPassword)"
    Write-Host ''
    Write-Info 'Save the key ID and the recovery key in your password manager now. Nothing is encrypted yet,'
    Write-Info 'and the key is not written to disk or uploaded: this window is the only copy.'
    $lastGroup = ($rp.RecoveryPassword -split '-')[-1]
    while ($true) {
        $typed = Read-Host 'From the saved entry, type the last 6 digits of the recovery key'
        if ("$typed".Trim() -eq $lastGroup) { break }
        Write-Warn 'That does not match. Check the saved entry and try again.'
    }
    Clear-Host

    # --- Enable: TPM + PIN, used space only. No -SkipHardwareTest: Windows checks at the next
    #     restart that the PIN can be entered before it starts encrypting. ---
    Enable-BitLocker -MountPoint $SystemDrive -EncryptionMethod XtsAes256 -UsedSpaceOnly `
        -TpmAndPinProtector -Pin $pin -WarningAction SilentlyContinue | Out-Null

    Write-Info 'BitLocker is set up (XTS-AES-256, TPM + PIN). Restart now: you will be asked for the PIN,'
    Write-Info "and encryption starts once Windows is back. Progress: manage-bde -status $SystemDrive"
    Write-Warn 'Without the saved recovery key, a forgotten PIN or a firmware change locks you out.'
    Write-Warn "Before any BIOS or GPU firmware update: manage-bde -protectors -disable $SystemDrive -RebootCount 1"
} catch {
    Write-Warn "BitLocker setup failed: $($_.Exception.Message)"
    $code = 1
}
Exit-Elevated -Code $code
