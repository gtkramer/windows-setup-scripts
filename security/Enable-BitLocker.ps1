#Requires -Version 5.1
<#
.SYNOPSIS
  Encrypt the system drive with BitLocker: XTS-AES-256, unlocked at boot by TPM plus a PIN you
  type here. The recovery key is written to a folder you choose and is never uploaded.
.DESCRIPTION
  Run it as your standard account; it elevates itself. Run it once after the NVIDIA and
  firmware installs and before restoring your files. Windows then checks at the next restart
  that PIN entry works, and starts encrypting once it does.
  Acts only on a drive that is not encrypted at all; in any other state it stops and explains.
.PARAMETER KeyDir
  Folder to write the recovery key to, for example a USB drive. Prompted for when omitted.
#>
param([string]$TargetUser, [string]$TargetSid, [string]$LogPath, [string]$KeyDir)
. (Join-Path $PSScriptRoot '..\common.ps1')

if (-not (Test-Admin)) {
    $forward = if ($KeyDir) { @('-KeyDir', "`"$KeyDir`"") } else { @() }
    exit (Invoke-Elevated -ScriptPath $PSCommandPath -ArgumentList $forward)
}

function Read-Plain {
    # Reads a secret without echo and returns it as text for comparison.
    param([string]$Prompt)
    $secure = Read-Host $Prompt -AsSecureString
    return [Net.NetworkCredential]::new('', $secure).Password
}

$code = 0
try {
    Enter-Elevated -TargetUser $TargetUser -TargetSid $TargetSid -LogPath $LogPath

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

    # --- Where the recovery key goes: anywhere but the drive being encrypted ---
    while ($true) {
        if (-not $KeyDir) { $KeyDir = Read-Host 'Folder to write the recovery key to (for example a USB drive, E:\)' }
        if (-not (Test-Path $KeyDir -PathType Container)) { Write-Warn "'$KeyDir' is not an existing folder."; $KeyDir = $null; continue }
        if ([IO.Path]::GetPathRoot((Resolve-Path $KeyDir).Path) -eq "$SystemDrive\") {
            Write-Warn "A recovery key stored on $SystemDrive is locked inside the drive it unlocks. Choose another drive."
            $KeyDir = $null; continue
        }
        break
    }

    # --- The PIN: typed twice, never written anywhere ---
    while ($true) {
        $pinText = Read-Plain 'BitLocker startup PIN (6 to 20 digits)'
        if ($pinText -notmatch '^\d{6,20}$') { Write-Warn 'The PIN must be 6 to 20 digits.'; continue }
        if ($pinText -ne (Read-Plain 'Type the PIN again')) { Write-Warn 'The two entries differ.'; continue }
        break
    }
    $pin = ConvertTo-SecureString $pinText -AsPlainText -Force
    $pinText = $null

    # --- Recovery password first, saved and checked before anything is encrypted ---
    # Warnings are silenced because BitLocker prints the recovery password in them, and this
    # window is logged.
    if ($types -notcontains 'RecoveryPassword') {
        Add-BitLockerKeyProtector -MountPoint $SystemDrive -RecoveryPasswordProtector -WarningAction SilentlyContinue | Out-Null
    }
    $rp = (Get-BitLockerVolume -MountPoint $SystemDrive).KeyProtector |
          Where-Object KeyProtectorType -eq 'RecoveryPassword' | Select-Object -Last 1
    if (-not $rp -or -not $rp.RecoveryPassword) { Die 'The recovery password was not created; nothing was encrypted.' }
    $keyFile = Join-Path $KeyDir "$HostName-recovery.txt"
    @(
        "BitLocker recovery - $HostName - $SystemDrive - $(Get-Date -Format 'yyyy-MM-dd')"
        "Recovery Key ID  : $($rp.KeyProtectorId)"
        "Recovery Password: $($rp.RecoveryPassword)"
    ) | Set-Content -Path $keyFile -Encoding ASCII
    if (-not (Select-String -Path $keyFile -SimpleMatch $rp.RecoveryPassword -Quiet)) {
        Die "Could not confirm the recovery key was written to $keyFile; nothing was encrypted."
    }
    Write-Info "Recovery key written to $keyFile. It is not uploaded anywhere."

    # --- Enable: TPM + PIN, used space only. No -SkipHardwareTest: Windows checks at the next
    #     restart that the PIN can be entered before it starts encrypting. ---
    Enable-BitLocker -MountPoint $SystemDrive -EncryptionMethod XtsAes256 -UsedSpaceOnly `
        -TpmAndPinProtector -Pin $pin -WarningAction SilentlyContinue | Out-Null

    Write-Info 'BitLocker is set up (XTS-AES-256, TPM + PIN). Restart now: you will be asked for the PIN,'
    Write-Info "and encryption starts once Windows is back. Progress: manage-bde -status $SystemDrive"
    Write-Warn "Move $keyFile to offline storage. Without it, a forgotten PIN or a firmware change locks you out."
    Write-Warn "Before any BIOS or GPU firmware update: manage-bde -protectors -disable $SystemDrive -RebootCount 1"
} catch {
    Write-Warn "BitLocker setup failed: $($_.Exception.Message)"
    $code = 1
}
Exit-Elevated -Code $code
