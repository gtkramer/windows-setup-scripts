#Requires -Version 5.1
# Shared by Enable-BitLocker.ps1 and Enable-BitLockerDataDrive.ps1. Dot-sourced after
# common.ps1; not run by hand.

function Set-BitLockerPolicy {
    # XTS-AES-256 for every drive type, and a startup PIN allowed. Must be in place before a
    # drive is encrypted: the cipher cannot be changed on an encrypted drive.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Thin wrapper over Set-RegistryValue, which supports ShouldProcess.')]
    param()
    $fve = 'HKLM:\SOFTWARE\Policies\Microsoft\FVE'
    Set-RegistryValue $fve 'EncryptionMethodWithXtsOs'  7
    Set-RegistryValue $fve 'EncryptionMethodWithXtsFdv' 7
    Set-RegistryValue $fve 'EncryptionMethodWithXtsRdv' 7
    Set-RegistryValue $fve 'UseAdvancedStartup' 1
    Set-RegistryValue $fve 'EnableBDEWithNoTPM' 0
    foreach ($name in 'UseTPM', 'UseTPMPIN', 'UseTPMKey', 'UseTPMKeyPIN') { Set-RegistryValue $fve $name 2 }   # 2 = allow
}

function Get-ProtectorType {
    # The key protector types on a BitLocker volume, as text ('TpmPin', 'RecoveryPassword', ...).
    param([Parameter(Mandatory)]$Volume)
    return @(@($Volume.KeyProtector) | Where-Object { $_ } | ForEach-Object { "$($_.KeyProtectorType)" })
}

function Confirm-RecoveryKey {
    # Creates the drive's recovery key if it has none, shows it, and returns only once you
    # have typed its last group back from your saved copy. The key is never written to disk.
    # BitLocker's own warnings are silenced because they repeat the key.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'The recovery key is shown on the console only, by design.')]
    param(
        [Parameter(Mandatory)][string]$MountPoint,
        [Parameter(Mandatory)][string]$Title    # the line to save with the key, e.g. host, drive, date
    )
    $volume = Get-BitLockerVolume -MountPoint $MountPoint -ErrorAction Stop
    if ((Get-ProtectorType $volume) -notcontains 'RecoveryPassword') {
        Add-BitLockerKeyProtector -MountPoint $MountPoint -RecoveryPasswordProtector `
            -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null
        $volume = Get-BitLockerVolume -MountPoint $MountPoint -ErrorAction Stop
    }
    $rp = @($volume.KeyProtector) | Where-Object { "$($_.KeyProtectorType)" -eq 'RecoveryPassword' } | Select-Object -Last 1
    if (-not $rp -or -not $rp.RecoveryPassword) { Die "The recovery key for $MountPoint could not be created or read; nothing was changed." }

    Write-Host ''
    Write-Host "  $Title"
    Write-Host "  Key ID       : $($rp.KeyProtectorId)"
    Write-Host "  Recovery key : $($rp.RecoveryPassword)"
    Write-Host ''
    Write-Info 'Save the title, the key ID and the recovery key in your password manager now.'
    Write-Info 'The key is not written to disk or uploaded: this window is the only copy.'
    $lastGroup = ($rp.RecoveryPassword -split '-')[-1]
    while ($true) {
        $typed = Read-Host 'From the saved entry, type the last 6 digits of the recovery key'
        if ("$typed".Trim() -eq $lastGroup) { break }
        Write-Warn 'That does not match. Check the saved entry and try again.'
    }
    Clear-Host
}
