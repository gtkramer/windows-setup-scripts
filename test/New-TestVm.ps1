#Requires -Version 5.1
<#
.SYNOPSIS
  Create and manage a Hyper-V test VM for rehearsing the install before touching the real PC:
  generation 2, Secure Boot, virtual TPM, the Microsoft ISO as the boot DVD, and a small "kit
  ISO" (the answer file plus this kit) as a second DVD. Run it from a normal terminal; it
  elevates itself.
.DESCRIPTION
  Hyper-V must be enabled:   Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All   (then restart)

    .\test\New-TestVm.ps1 -WinIso C:\iso\Win11.iso -Start    create the VM and boot it into Windows Setup
    .\test\New-TestVm.ps1 -RefreshKit                        rebuild the kit ISO after editing a script
    .\test\New-TestVm.ps1 -Start                             start the VM and open its console
    .\test\New-TestVm.ps1 -Remove                            delete the VM and its files

  Windows Setup finds autounattend.xml on the second DVD. After setup, run
  <DVD>:\windows-setup-scripts\Install.ps1 inside the VM. The full procedure is in the README.
  Limits: a VM does not reproduce the graphics card's effect on BitLocker, and an unactivated
  Windows greys out the Personalization pages.
.PARAMETER WinIso
  The Windows 11 ISO from Microsoft. Creates the VM.
.PARAMETER DataDisk
  With -WinIso: add a second, empty 20 GB disk for rehearsing security\Enable-BitLockerDataDrive.ps1.
.PARAMETER Start
  Start the VM and open its console. With -WinIso it also presses a key for you at "Press any
  key to boot from CD or DVD", for the first seconds only, so the new VM boots into Setup.
.PARAMETER RefreshKit
  Rebuild the kit ISO from this folder and put it back in the VM's DVD drive, running or not.
  Inside the VM the DVD then holds your edited scripts: no reinstall of Windows.
.PARAMETER Remove
  Turn the VM off and delete it, its disks, its checkpoints and its kit ISO.
#>
param(
    [string]$TargetUser,
    [string]$WinIso,
    [string]$Name = 'W11-kit-test',
    [string]$VmRoot = (Join-Path $env:ProgramData 'windows-setup-scripts\vm'),
    [switch]$DataDisk,
    [switch]$Start,
    [switch]$RefreshKit,
    [switch]$Remove
)
. (Join-Path $PSScriptRoot '..\common.ps1')

$usage = 'Usage: .\test\New-TestVm.ps1 -WinIso <Windows ISO> [-DataDisk] [-Start]  |  -RefreshKit [-Start]  |  -Start  |  -Remove'
$actions = @(@([bool]$WinIso, [bool]$RefreshKit, [bool]$Remove) | Where-Object { $_ })
if ($actions.Count -gt 1 -or ($actions.Count -eq 0 -and -not $Start)) { Die $usage }
if ($Remove -and $Start)        { Die $usage }
if ($DataDisk -and -not $WinIso) { Die "-DataDisk goes with -WinIso. $usage" }
# The name becomes a folder that -Remove deletes, so keep it to a plain name.
if ($Name -notmatch '^[A-Za-z0-9][A-Za-z0-9 ._-]{0,60}$') { Die "VM name '$Name' must be letters, digits, spaces, dots, hyphens or underscores." }

if (-not (Test-Admin)) {
    $forward = @('-Name', "`"$Name`"", '-VmRoot', "`"$VmRoot`"")
    if ($WinIso) {
        # The elevated window starts in another folder, so pass the full path.
        if (-not (Test-Path $WinIso -PathType Leaf)) { Die "ISO not found: $WinIso" }
        $forward += @('-WinIso', "`"$((Resolve-Path $WinIso).Path)`"")
    }
    foreach ($flag in 'DataDisk', 'Start', 'RefreshKit', 'Remove') {
        if ((Get-Variable -Name $flag -ValueOnly)) { $forward += "-$flag" }
    }
    exit (Invoke-Elevated -ScriptPath $PSCommandPath -ArgumentList $forward)
}

$vmDir  = Join-Path $VmRoot $Name
$kitIso = Join-Path $VmRoot "$Name-kit.iso"

function New-DataIso {
    # Builds a plain (non-bootable) ISO from a folder with Windows' own IMAPI2 component.
    param([Parameter(Mandatory)][string]$SourceDir, [Parameter(Mandatory)][string]$IsoFile, [string]$Label = 'KITMEDIA')
    if (-not ('KitIsoStreamWriter' -as [type])) {
        Add-Type -TypeDefinition @'
using System; using System.IO; using System.Runtime.InteropServices.ComTypes;
public static class KitIsoStreamWriter {
    public static void Write(object stream, string path, int blockSize, int blocks) {
        IStream source = (IStream)stream; byte[] buffer = new byte[blockSize];
        using (FileStream file = File.Create(path)) {
            for (int i = 0; i < blocks; i++) { source.Read(buffer, blockSize, IntPtr.Zero); file.Write(buffer, 0, blockSize); }
        }
    }
}
'@
    }
    $image = New-Object -ComObject IMAPI2FS.MsftFileSystemImage
    $image.FileSystemsToCreate = 3      # ISO 9660 + Joliet
    $image.VolumeName = $Label
    $image.FreeMediaBlocks = 0          # no size limit
    $image.Root.AddTree((Resolve-Path $SourceDir).Path, $false)
    $result = $image.CreateResultImage()
    [KitIsoStreamWriter]::Write($result.ImageStream, $IsoFile, $result.BlockSize, $result.TotalBlocks)
}

function New-KitIso {
    # The kit ISO: the answer file at its root, the kit in a folder beside it.
    $stage = Join-Path $env:TEMP ("kit-iso-" + [guid]::NewGuid().ToString('N'))
    try {
        New-Item $stage -ItemType Directory -Force | Out-Null
        Copy-Item (Join-Path $KitRoot 'media\autounattend.xml') (Join-Path $stage 'autounattend.xml')
        robocopy $KitRoot (Join-Path $stage 'windows-setup-scripts') /E /XD .git /NFL /NDL /NJH /NJS /NP | Out-Null
        if ($LASTEXITCODE -ge 8) { Die "Copying the kit failed (robocopy exit $LASTEXITCODE)." }
        if (-not (Test-Path $VmRoot)) { New-Item $VmRoot -ItemType Directory -Force | Out-Null }
        if (Test-Path $kitIso) { Remove-Item $kitIso -Force }
        New-DataIso -SourceDir $stage -IsoFile $kitIso
        Write-Info "Kit ISO written: $kitIso"
    } finally {
        if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
    }
}

function Send-BootKey {
    # A new VM boots from the Windows DVD only if a key is pressed at "Press any key to boot from
    # CD or DVD". Press the space bar through Hyper-V's virtual keyboard for the first seconds,
    # then stop, well before Windows Setup shows anything a key press could change.
    param([int]$Seconds = 10)
    $sent = 0
    try {
        $system = Get-CimInstance -Namespace 'root\virtualization\v2' -ClassName Msvm_ComputerSystem `
                      -Filter "ElementName='$Name'" -ErrorAction Stop
        $until = (Get-Date).AddSeconds($Seconds)
        while ((Get-Date) -lt $until) {
            $keyboard = Get-CimAssociatedInstance -InputObject $system -ResultClassName Msvm_Keyboard -ErrorAction SilentlyContinue
            if ($keyboard) {
                $result = Invoke-CimMethod -InputObject $keyboard -MethodName TypeKey -Arguments @{ keyCode = [uint32]32 } -ErrorAction SilentlyContinue
                if ($result -and $result.ReturnValue -eq 0) { $sent++ }
            }
            Start-Sleep -Milliseconds 300
        }
    } catch {
        Write-Warn "The boot key press failed: $($_.Exception.Message)"
    }
    if ($sent -eq 0) { Write-Warn 'No key press reached the VM. In its console window, press a key at "Press any key to boot from CD or DVD"; restart the VM if the prompt has passed.' }
}

function Start-TestVm {
    param([switch]$PressBootKey)
    if ((Get-VM -Name $Name).State -ne 'Running') { Start-VM -Name $Name }
    Start-Process -FilePath "$env:SystemRoot\System32\vmconnect.exe" -ArgumentList 'localhost', "`"$Name`""
    if ($PressBootKey) { Send-BootKey }
    Write-Info "VM $Name is running; its console window is open. In the console's View menu, keep Enhanced Session off: PIN screens need the basic session."
}

$code = 0
try {
    Enter-Elevated -TargetUser $TargetUser

    if (-not (Get-Command New-VM -ErrorAction SilentlyContinue)) {
        Die 'Hyper-V is not enabled. Run (elevated), then restart:  Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All'
    }
    if ((Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'TypeOfAdminApprovalMode') -eq 2) {
        Write-Warn 'Administrator protection is on on this PC. Microsoft lists "devices that require Hyper-V" under when not to enable it, without saying what fails. If the VM misbehaves, turn it off and restart first (see README).'
    }
    $vm = Get-VM -Name $Name -ErrorAction SilentlyContinue

    if ($Remove) {
        # --- Delete the VM and everything this script made for it ---
        if ($vm) {
            $outside = @(Get-VMHardDiskDrive -VMName $Name | ForEach-Object { $_.Path } |
                         Where-Object { $_ -and -not $_.StartsWith("$vmDir\", [StringComparison]::OrdinalIgnoreCase) })
            if ($outside.Count -gt 0) {
                Die "VM $Name was not made by this script: its disk $($outside[0]) is outside $vmDir. Remove it in Hyper-V Manager."
            }
            if ($vm.State -ne 'Off') { Stop-VM -Name $Name -TurnOff -Force }
            Remove-VM -Name $Name -Force
        }
        $found = [bool]$vm
        foreach ($leftover in $vmDir, $kitIso) {
            if (Test-Path -LiteralPath $leftover) { Remove-Item -LiteralPath $leftover -Recurse -Force; $found = $true }
        }
        if ($found) { Write-Info "VM $Name removed, with its disks, checkpoints and kit ISO." }
        else        { Write-Info "Nothing to remove: there is no VM named $Name and no files for it in $VmRoot." }
    } elseif ($RefreshKit) {
        # --- Rebuild the kit ISO and put it back in the DVD drive it was in ---
        if (-not $vm) { Die "There is no VM named $Name. Create it first with -WinIso." }
        $drives = @(Get-VMDvdDrive -VMName $Name | Sort-Object ControllerNumber, ControllerLocation)
        $drive  = $drives | Where-Object { $_.Path -eq $kitIso } | Select-Object -First 1
        if (-not $drive) { $drive = $drives | Where-Object { -not $_.Path } | Select-Object -Last 1 }   # ejected for a BitLocker test
        if (-not $drive) { Die "VM $Name has no DVD drive that holds the kit ISO or is empty." }
        $where = @{ VMName = $Name; ControllerNumber = $drive.ControllerNumber; ControllerLocation = $drive.ControllerLocation }
        Set-VMDvdDrive @where -Path $null      # release the old ISO so it can be replaced
        New-KitIso
        Set-VMDvdDrive @where -Path $kitIso
        Write-Info "The VM's DVD drive holds the rebuilt kit. Inside the VM, run the scripts from that drive again."
        Write-Info "Before a BitLocker test, eject it again:  Get-VMDvdDrive -VMName $Name | Set-VMDvdDrive -Path `$null"
        if ($Start) { Start-TestVm }
    } elseif ($WinIso) {
        # --- Create the VM ---
        if (-not (Test-Path $WinIso -PathType Leaf)) { Die "ISO not found: $WinIso" }
        if ($vm) { Die "A VM named $Name already exists. Remove it with -Remove, or pass -Name." }
        New-KitIso

        New-VM -Name $Name -Generation 2 -Path $VmRoot -MemoryStartupBytes 8GB `
            -NewVHDPath (Join-Path $vmDir "$Name.vhdx") -NewVHDSizeBytes 100GB -SwitchName 'Default Switch' | Out-Null
        Set-VMMemory    -VMName $Name -DynamicMemoryEnabled $false
        Set-VMProcessor -VMName $Name -Count 4
        Set-VM -Name $Name -AutomaticCheckpointsEnabled $false -CheckpointType Standard -AutomaticStopAction ShutDown
        Set-VMFirmware  -VMName $Name -EnableSecureBoot On -SecureBootTemplate MicrosoftWindows
        Set-VMKeyProtector -VMName $Name -NewLocalKeyProtector
        Enable-VMTPM    -VMName $Name
        $bootDvd = Add-VMDvdDrive -VMName $Name -Path (Resolve-Path $WinIso).Path -Passthru
        Add-VMDvdDrive  -VMName $Name -Path $kitIso
        Set-VMFirmware  -VMName $Name -FirstBootDevice $bootDvd
        if ($DataDisk) {
            $dataVhd = Join-Path $vmDir "$Name-data.vhdx"
            New-VHD -Path $dataVhd -SizeBytes 20GB -Dynamic | Out-Null
            Add-VMHardDiskDrive -VMName $Name -Path $dataVhd
        }

        Write-Info "VM $Name created (4 processors, 8 GB, 100 GB disk, Secure Boot, TPM$(if ($DataDisk) { ', 20 GB data disk' }))."
        if ($Start) { Start-TestVm -PressBootKey }
        else { Write-Info 'Start it:        .\test\New-TestVm.ps1 -Start    (then press a key at the boot prompt; -WinIso with -Start presses it for you)' }
        Write-Info "Snapshot it:     Checkpoint-VM -Name $Name -SnapshotName clean-install      (from an elevated terminal)"
        Write-Info 'After an edit:   .\test\New-TestVm.ps1 -RefreshKit'
        Write-Info "Before BitLocker tests, eject the DVDs:  Get-VMDvdDrive -VMName $Name | Set-VMDvdDrive -Path `$null"
        if ($DataDisk) {
            Write-Info 'Windows Setup lists two disks: install to the 100 GB one. Then format the data disk inside the VM (elevated):'
            Write-Info '  Get-Disk | Where-Object PartitionStyle -eq RAW | Initialize-Disk -PartitionStyle GPT -PassThru | New-Partition -UseMaximumSize -AssignDriveLetter | Format-Volume -FileSystem NTFS -NewFileSystemLabel Data'
            Write-Info 'A checkpoint also reverts the data disk. To rehearse the rebuild case, run Clear-BitLockerAutoUnlock (elevated) and restart: the data disk is then locked.'
        }
    } else {
        # --- -Start alone: an existing VM. No key press: an installed VM must not boot the DVD again. ---
        if (-not $vm) { Die "There is no VM named $Name. Create it first with -WinIso." }
        Start-TestVm
    }
} catch {
    Write-Warn "VM script failed: $($_.Exception.Message)"
    $code = 1
}
Exit-Elevated -Code $code
