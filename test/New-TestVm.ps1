#Requires -Version 5.1
<#
.SYNOPSIS
  Create a Hyper-V test VM for rehearsing the install before touching the real PC: generation 2,
  Secure Boot, virtual TPM, the Microsoft ISO as the boot DVD and the kit ISO as a second DVD.
  Run it as yourself; it elevates itself.
.DESCRIPTION
  Build the kit ISO first:   .\media\New-InstallMedia.ps1 -KitIsoPath C:\path\kit.iso
  Hyper-V must be enabled:   Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All   (then restart)
  Windows Setup finds autounattend.xml on the second DVD. After setup, run
  <DVD>:\windows-setup-scripts\Install.ps1 inside the VM as the standard user.
  Limits: a VM does not reproduce the graphics card's effect on BitLocker, and an unactivated
  Windows greys out the Personalization pages.
.PARAMETER WinIso
  The Windows 11 ISO from Microsoft.
.PARAMETER KitIso
  The data ISO written by media\New-InstallMedia.ps1 -KitIsoPath.
#>
param(
    [string]$TargetUser, [string]$TargetSid, [string]$LogPath,
    [string]$WinIso,
    [string]$KitIso,
    [string]$Name = 'W11-kit-test',
    [string]$VmRoot = (Join-Path $env:ProgramData 'windows-setup-scripts\vm')
)
. (Join-Path $PSScriptRoot '..\common.ps1')

if (-not $WinIso -or -not $KitIso) { Die 'Usage: .\test\New-TestVm.ps1 -WinIso <Windows ISO> -KitIso <kit ISO>' }

if (-not (Test-Admin)) {
    $forward = @('-WinIso', "`"$WinIso`"", '-KitIso', "`"$KitIso`"", '-Name', "`"$Name`"", '-VmRoot', "`"$VmRoot`"")
    exit (Invoke-Elevated -ScriptPath $PSCommandPath -ArgumentList $forward)
}

$code = 0
try {
    Enter-Elevated -TargetUser $TargetUser -TargetSid $TargetSid -LogPath $LogPath

    if (-not (Get-Command New-VM -ErrorAction SilentlyContinue)) {
        Die 'Hyper-V is not enabled. Run (elevated), then restart:  Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All'
    }
    foreach ($iso in $WinIso, $KitIso) { if (-not (Test-Path $iso -PathType Leaf)) { Die "ISO not found: $iso" } }
    if (Get-VM -Name $Name -ErrorAction SilentlyContinue) { Die "A VM named $Name already exists. Remove it or pass -Name." }

    New-VM -Name $Name -Generation 2 -Path $VmRoot -MemoryStartupBytes 8GB `
        -NewVHDPath (Join-Path $VmRoot "$Name\$Name.vhdx") -NewVHDSizeBytes 100GB -SwitchName 'Default Switch' | Out-Null
    Set-VMMemory    -VMName $Name -DynamicMemoryEnabled $false
    Set-VMProcessor -VMName $Name -Count 4
    Set-VM -Name $Name -AutomaticCheckpointsEnabled $false -CheckpointType Standard -AutomaticStopAction ShutDown
    Set-VMFirmware  -VMName $Name -EnableSecureBoot On -SecureBootTemplate MicrosoftWindows
    Set-VMKeyProtector -VMName $Name -NewLocalKeyProtector
    Enable-VMTPM    -VMName $Name
    $bootDvd = Add-VMDvdDrive -VMName $Name -Path (Resolve-Path $WinIso).Path -Passthru
    Add-VMDvdDrive  -VMName $Name -Path (Resolve-Path $KitIso).Path
    Set-VMFirmware  -VMName $Name -FirstBootDevice $bootDvd

    Write-Info "VM $Name created (4 processors, 8 GB, 100 GB disk, Secure Boot, TPM)."
    Write-Info "Start it:        Start-VM $Name; vmconnect.exe localhost $Name    (press a key at the boot prompt)"
    Write-Info "Snapshot it:     Checkpoint-VM -Name $Name -SnapshotName clean-install"
    Write-Info "Before BitLocker tests, eject the DVDs:  Get-VMDvdDrive -VMName $Name | Set-VMDvdDrive -Path `$null"
} catch {
    Write-Warn "VM creation failed: $($_.Exception.Message)"
    $code = 1
}
Exit-Elevated -Code $code
