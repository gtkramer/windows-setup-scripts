#Requires -Version 5.1
<#
.SYNOPSIS
  Encrypt another internal drive with BitLocker (XTS-AES-256) and have it unlock by itself
  once the system drive is unlocked. Also reconnects a drive that is already encrypted, for
  example after Windows has been reinstalled: it then asks for that drive's recovery key.
.DESCRIPTION
  Run it from a normal terminal, once per drive, with the drive connected and formatted; it
  elevates itself. The system drive must already be protected: run Enable-BitLocker.ps1,
  restart, and let it finish encrypting first.
  The drive's recovery key is shown once for your password manager and never written to a
  file. The key that unlocks the drive automatically is kept by Windows on the system drive,
  so reinstalling Windows removes it; the recovery key is then the only way back in.
  Safe to re-run: it finishes what is missing and changes nothing else.
.PARAMETER Drive
  The drive letter, for example D:
.PARAMETER Full
  Also encrypt free space. Use it for a drive that has ever held unencrypted files you would
  mind someone recovering: deleted files linger in free space. Takes hours on a large hard
  disk; without it only the space in use is encrypted, which is all a new or empty drive needs.
#>
param(
    [string]$TargetUser,
    [string]$Drive,
    [switch]$Full
)
. (Join-Path $PSScriptRoot '..\common.ps1')
. (Join-Path $PSScriptRoot 'bitlocker.ps1')

if ("$Drive" -notmatch '^[A-Za-z]:?\\?$') { Die 'Usage: .\security\Enable-BitLockerDataDrive.ps1 -Drive D: [-Full]' }
$Drive = "$("$Drive".Substring(0, 1).ToUpper()):"
if ($Drive -eq $SystemDrive) { Die "$Drive is the system drive. Use security\Enable-BitLocker.ps1 for it." }

if (-not (Test-Admin)) {
    $forward = @('-Drive', $Drive)
    if ($Full) { $forward += '-Full' }
    exit (Invoke-Elevated -ScriptPath $PSCommandPath -ArgumentList $forward)
}

$code = 0
try {
    Enter-Elevated -TargetUser $TargetUser

    # --- The drive must be an internal (fixed) data drive ---
    $ev = Get-CimInstance -Namespace 'root/cimv2/Security/MicrosoftVolumeEncryption' `
              -ClassName Win32_EncryptableVolume -ErrorAction Stop |
          Where-Object { $_.DriveLetter -eq $Drive }
    if (-not $ev) { Die "$Drive was not found. Connect the drive and, if it is new, format it (NTFS) with a drive letter in Disk Management." }
    if ($ev.VolumeType -ne 1) {   # 0 = system, 1 = fixed data, 2 = removable
        Die @"
Windows treats $Drive as a removable drive, not an internal one, and removable drives unlock
per user account, not for the PC. This happens to a disk on a SATA port with hot-plug turned
on: turn hot-plug off for that port in the BIOS and re-run.
"@
    }

    # --- The system drive must be protected: the automatic-unlock key is stored on it ---
    $os = Get-BitLockerVolume -MountPoint $SystemDrive -ErrorAction Stop
    if ("$($os.ProtectionStatus)" -ne 'On' -or (Get-ProtectorType $os) -notcontains 'TpmPin') {
        Die "$SystemDrive is not protected yet (status $($os.VolumeStatus), protection $($os.ProtectionStatus)). Run security\Enable-BitLocker.ps1, restart, wait until manage-bde -status $SystemDrive shows it fully encrypted with protection on, then re-run."
    }

    $vol = Get-BitLockerVolume -MountPoint $Drive -ErrorAction Stop

    # --- Locked: an encrypted drive this Windows install has not seen (after a rebuild) ---
    if ("$($vol.LockStatus)" -eq 'Locked') {
        $keyIds = @(@($vol.KeyProtector) | Where-Object { "$($_.KeyProtectorType)" -eq 'RecoveryPassword' } |
                    ForEach-Object { $_.KeyProtectorId })
        if ($keyIds.Count -eq 0) { Die "$Drive is locked and has no recovery key, so this script cannot unlock it." }
        Write-Info "$Drive is encrypted and locked. Find its recovery key in your password manager by key ID:"
        $keyIds | ForEach-Object { Write-Info "  $_" }
        while ($true) {
            $typed = Read-Host 'Recovery key for this drive (48 digits; Enter alone cancels)'
            if (-not "$typed".Trim()) { Die "Cancelled. $Drive is still locked." }
            $digits = "$typed" -replace '\D'
            if ($digits.Length -ne 48) { Write-Warn 'A recovery key has 48 digits.'; continue }
            $key = (($digits -split '(.{6})') -ne '') -join '-'
            try {
                Unlock-BitLocker -MountPoint $Drive -RecoveryPassword $key -ErrorAction Stop | Out-Null
                break
            } catch {
                Write-Warn "That key did not unlock $Drive`: $($_.Exception.Message)"
            }
        }
        Clear-Host
        Write-Info "$Drive unlocked."
        $vol = Get-BitLockerVolume -MountPoint $Drive -ErrorAction Stop
    }

    $types   = Get-ProtectorType $vol
    $status  = "$($vol.VolumeStatus)"
    $summary = "status $status, protection $($vol.ProtectionStatus), method $($vol.EncryptionMethod), protectors [$($types -join ', ')]"
    $label   = try { "$((Get-Volume -DriveLetter $Drive.Substring(0, 1) -ErrorAction Stop).FileSystemLabel)" } catch { '' }
    $title   = "BitLocker recovery key - $HostName - $Drive ($(if ($label) { $label } else { 'no label' })) - $(Get-Date -Format 'yyyy-MM-dd')"
    $fresh   = $false

    if ($status -eq 'FullyDecrypted') {
        # --- Not encrypted. A recovery key alone is left over from an interrupted run: reuse it. ---
        if (@($types | Where-Object { $_ -ne 'RecoveryPassword' }).Count -gt 0) {
            Die "$Drive is in a state this script does not change:`n  $summary"
        }
        Set-BitLockerPolicy
        Confirm-RecoveryKey -MountPoint $Drive -Title $title

        # manage-bde starts encryption with the recovery key already on the drive; every
        # Enable-BitLocker form would add a second key. Its text is shown only on failure.
        $bde = @('-on', $Drive, '-EncryptionMethod', 'xts_aes256')
        if (-not $Full) { $bde += '-UsedSpaceOnly' }
        $out = & "$env:SystemRoot\System32\manage-bde.exe" @bde
        $bdeExit = $LASTEXITCODE
        $vol = Get-BitLockerVolume -MountPoint $Drive -ErrorAction Stop
        if ($bdeExit -ne 0 -or "$($vol.VolumeStatus)" -eq 'FullyDecrypted' -or "$($vol.EncryptionMethod)" -ne 'XtsAes256') {
            Die "Encryption did not start on $Drive (manage-bde exit $bdeExit).`n$($out -join "`n")"
        }
        $fresh = $true
    } elseif ($status -notin 'EncryptionInProgress', 'FullyEncrypted', 'FullyEncryptedWipeInProgress' -or
              "$($vol.EncryptionMethod)" -ne 'XtsAes256') {
        Die @"
$Drive is in a state this script does not change:
  $summary
The cipher cannot be changed on an encrypted drive. To start over, decrypt it first
(manage-bde -off $Drive, wait for 'Fully Decrypted' in manage-bde -status $Drive), then re-run.
"@
    } elseif ($status -eq 'FullyEncrypted' -and "$($vol.ProtectionStatus)" -ne 'On') {
        Die "$Drive is encrypted but its protection is suspended. Resume it (Resume-BitLocker -MountPoint $Drive), then re-run."
    } elseif ($types -notcontains 'RecoveryPassword') {
        Confirm-RecoveryKey -MountPoint $Drive -Title $title
    }

    # --- Automatic unlock, tied to this Windows install ---
    $vol = Get-BitLockerVolume -MountPoint $Drive -ErrorAction Stop
    if ($vol.AutoUnlockEnabled -eq $true) {
        Write-Info "$Drive already unlocks automatically."
    } else {
        # The kit never creates key files, so an external key here is the automatic-unlock
        # key of an earlier Windows install. It is useless now; remove it.
        $stale = @(@($vol.KeyProtector) | Where-Object { "$($_.KeyProtectorType)" -eq 'ExternalKey' })
        foreach ($kp in $stale) {
            Remove-BitLockerKeyProtector -MountPoint $Drive -KeyProtectorId $kp.KeyProtectorId -ErrorAction Stop | Out-Null
        }
        if ($stale.Count -gt 0) { Write-Info "Removed $($stale.Count) automatic-unlock key(s) left by an earlier Windows install." }
        Enable-BitLockerAutoUnlock -MountPoint $Drive -ErrorAction Stop | Out-Null
        $vol = Get-BitLockerVolume -MountPoint $Drive -ErrorAction Stop
        if ($vol.AutoUnlockEnabled -ne $true) { Die "Automatic unlock could not be turned on for $Drive. Re-run this script." }
        Write-Info "$Drive now unlocks automatically once $SystemDrive is unlocked."
    }

    Write-Info "$Drive`: $($vol.VolumeStatus), $($vol.EncryptionMethod), $($vol.EncryptionPercentage)% encrypted."
    if ("$($vol.VolumeStatus)" -ne 'FullyEncrypted') {
        Write-Info "Encryption runs in the background and resumes after a restart. Keep the drive connected until manage-bde -status $Drive shows 100%."
    }
    if ($fresh -and -not $Full) {
        Write-Info "Only the space in use was encrypted. If this drive ever held unencrypted files, also run: manage-bde -WipeFreeSpace $Drive"
    }
    Write-Warn "Reinstalling Windows removes the automatic unlock. You then need this drive's recovery key: re-run this script and type it."
} catch {
    Write-Warn "BitLocker setup for $Drive failed: $($_.Exception.Message)"
    $code = 1
}
Exit-Elevated -Code $code
