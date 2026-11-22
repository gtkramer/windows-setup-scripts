#Requires -Version 5.1
<#
.SYNOPSIS
  Create a Hyper-V test VM for rehearsing the install before touching the real PC: generation 2,
  Secure Boot, virtual TPM, the Microsoft ISO as the boot DVD, and a small "kit ISO" (the answer
  file plus this kit) as a second DVD. Run it from a normal terminal; it elevates itself.
.DESCRIPTION
  Hyper-V must be enabled:   Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All   (then restart)
  Windows Setup finds autounattend.xml on the second DVD. After setup, run
  <DVD>:\windows-setup-scripts\Install.ps1 inside the VM.
  Limits: a VM does not reproduce the graphics card's effect on BitLocker, and an unactivated
  Windows greys out the Personalization pages.
.PARAMETER WinIso
  The Windows 11 ISO from Microsoft (the Media Creation Tool can save one).
#>
param(
    [string]$TargetUser,
    [string]$WinIso,
    [string]$Name = 'W11-kit-test',
    [string]$VmRoot = (Join-Path $env:ProgramData 'windows-setup-scripts\vm')
)
. (Join-Path $PSScriptRoot '..\common.ps1')

if (-not $WinIso) { Die 'Usage: .\test\New-TestVm.ps1 -WinIso <Windows ISO>' }

if (-not (Test-Admin)) {
    $forward = @('-WinIso', "`"$WinIso`"", '-Name', "`"$Name`"", '-VmRoot', "`"$VmRoot`"")
    exit (Invoke-Elevated -ScriptPath $PSCommandPath -ArgumentList $forward)
}

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

$code = 0
$stage = $null
try {
    Enter-Elevated -TargetUser $TargetUser

    if (-not (Get-Command New-VM -ErrorAction SilentlyContinue)) {
        Die 'Hyper-V is not enabled. Run (elevated), then restart:  Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All'
    }
    if (-not (Test-Path $WinIso -PathType Leaf)) { Die "ISO not found: $WinIso" }
    if (Get-VM -Name $Name -ErrorAction SilentlyContinue) { Die "A VM named $Name already exists. Remove it or pass -Name." }

    # --- The kit ISO: the answer file at its root, the kit in a folder beside it ---
    $stage = Join-Path $env:TEMP ("kit-iso-" + [guid]::NewGuid().ToString('N'))
    New-Item $stage -ItemType Directory -Force | Out-Null
    Copy-Item (Join-Path $KitRoot 'media\autounattend.xml') (Join-Path $stage 'autounattend.xml')
    robocopy $KitRoot (Join-Path $stage 'windows-setup-scripts') /E /XD .git /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { Die "Copying the kit failed (robocopy exit $LASTEXITCODE)." }
    if (-not (Test-Path $VmRoot)) { New-Item $VmRoot -ItemType Directory -Force | Out-Null }
    $kitIso = Join-Path $VmRoot "$Name-kit.iso"
    if (Test-Path $kitIso) { Remove-Item $kitIso -Force }
    New-DataIso -SourceDir $stage -IsoFile $kitIso
    Write-Info "Kit ISO written: $kitIso"

    # --- The VM ---
    New-VM -Name $Name -Generation 2 -Path $VmRoot -MemoryStartupBytes 8GB `
        -NewVHDPath (Join-Path $VmRoot "$Name\$Name.vhdx") -NewVHDSizeBytes 100GB -SwitchName 'Default Switch' | Out-Null
    Set-VMMemory    -VMName $Name -DynamicMemoryEnabled $false
    Set-VMProcessor -VMName $Name -Count 4
    Set-VM -Name $Name -AutomaticCheckpointsEnabled $false -CheckpointType Standard -AutomaticStopAction ShutDown
    Set-VMFirmware  -VMName $Name -EnableSecureBoot On -SecureBootTemplate MicrosoftWindows
    Set-VMKeyProtector -VMName $Name -NewLocalKeyProtector
    Enable-VMTPM    -VMName $Name
    $bootDvd = Add-VMDvdDrive -VMName $Name -Path (Resolve-Path $WinIso).Path -Passthru
    Add-VMDvdDrive  -VMName $Name -Path $kitIso
    Set-VMFirmware  -VMName $Name -FirstBootDevice $bootDvd

    Write-Info "VM $Name created (4 processors, 8 GB, 100 GB disk, Secure Boot, TPM)."
    Write-Info "Start it:        Start-VM $Name; vmconnect.exe localhost $Name    (press a key at the boot prompt)"
    Write-Info "Snapshot it:     Checkpoint-VM -Name $Name -SnapshotName clean-install"
    Write-Info "Before BitLocker tests, eject the DVDs:  Get-VMDvdDrive -VMName $Name | Set-VMDvdDrive -Path `$null"
} catch {
    Write-Warn "VM creation failed: $($_.Exception.Message)"
    $code = 1
} finally {
    if ($stage -and (Test-Path $stage)) { Remove-Item $stage -Recurse -Force }
}
Exit-Elevated -Code $code
