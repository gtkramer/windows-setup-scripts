#Requires -Version 5.1
<#
.SYNOPSIS
  Build the Windows 11 install USB: the Microsoft ISO's contents, the answer file filled in
  from common.ps1, and a copy of this kit. Run it as yourself; it elevates itself.
.DESCRIPTION
  1) Checks the ISO's SHA-256.
  2) Wipes the chosen USB stick (after a typed confirmation) and formats it GPT / FAT32.
  3) Copies the ISO; install.wim is split with DISM because FAT32 cannot hold files over 4 GB.
  4) Asks for the two account passwords and writes autounattend.xml to the stick's root.
     The passwords exist only on the stick (in reversible form); Install.ps1 removes the file.
  5) Copies the kit to \windows-setup-scripts on the stick.
  With -KitIsoPath it builds no USB: it writes a small data ISO holding the answer file and
  the kit, to attach to a test VM as a second DVD drive (see test\New-TestVm.ps1).
.PARAMETER IsoPath
  The Windows 11 multi-edition x64 ISO from https://www.microsoft.com/software-download/windows11
.PARAMETER IsoSha256
  The SHA-256 Microsoft publishes for that ISO. When omitted, the hash is shown for you to compare.
.PARAMETER DiskNumber
  The USB stick's disk number (see Get-Disk). Prompted for when omitted.
.PARAMETER KitIsoPath
  Write a data ISO for VM testing to this path, and do not touch any USB stick.
#>
param(
    [string]$TargetUser, [string]$TargetSid, [string]$LogPath,
    [string]$IsoPath,
    [string]$IsoSha256,
    [int]$DiskNumber = -1,
    [string]$KitIsoPath
)
. (Join-Path $PSScriptRoot '..\common.ps1')

if (-not (Test-Admin)) {
    $forward = @()
    if ($IsoPath)          { $forward += @('-IsoPath', "`"$IsoPath`"") }
    if ($IsoSha256)        { $forward += @('-IsoSha256', $IsoSha256) }
    if ($DiskNumber -ge 0) { $forward += @('-DiskNumber', $DiskNumber) }
    if ($KitIsoPath)       { $forward += @('-KitIsoPath', "`"$KitIsoPath`"") }
    exit (Invoke-Elevated -ScriptPath $PSCommandPath -ArgumentList $forward)
}

function Read-NewPassword {
    # Asks twice without echo; returns the password as text. Never logged.
    param([string]$Account)
    while ($true) {
        $first = [Net.NetworkCredential]::new('', (Read-Host "Password for $Account" -AsSecureString)).Password
        if ($first.Length -lt 8) { Write-Warn 'Use at least 8 characters.'; continue }
        $again = [Net.NetworkCredential]::new('', (Read-Host "Type the password for $Account again" -AsSecureString)).Password
        if ($first -cne $again) { Write-Warn 'The two entries differ.'; continue }
        return $first
    }
}

function ConvertTo-XmlText {
    # XML-escapes a value and turns non-ASCII characters into numeric references: Windows Setup
    # wants the answer file as UTF-8 without a byte-order mark and without raw non-ASCII.
    param([string]$Text)
    $escaped = [Security.SecurityElement]::Escape($Text)
    return [regex]::Replace($escaped, '[^\x20-\x7E]', { param($m) '&#x{0:X};' -f [int][char]$m.Value })
}

function ConvertTo-UnattendPassword {
    # Windows' own obscuring for answer-file passwords: Base64 of UTF-16LE(password + 'Password').
    param([string]$Password)
    return [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Password + 'Password'))
}

function New-AnswerFile {
    # Fills the generated template (media\autounattend.xml) with the values from common.ps1 and
    # the two passwords, and writes it as UTF-8 without a byte-order mark.
    param([Parameter(Mandatory)][string]$OutFile)

    if ($HostName -notmatch '^(?!\d+$)[A-Za-z0-9-]{1,15}$') { Die "HostName '$HostName' must be 1-15 letters, digits or hyphens." }
    foreach ($name in $UserName, $AdminName) {
        if ($name.Length -gt 20 -or $name -match '[/\\\[\]:;|=,+*?<>"%]' -or $name.EndsWith('.')) { Die "Account name '$name' is not valid for Windows." }
    }

    $template = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'autounattend.xml'))
    # Placeholder tokens in the template, and how many times each must appear outside the
    # generator's URL comment. A mismatch means the template was regenerated differently.
    $template = [regex]::Replace($template, '(?s)[ \t]*<!--https://schneegans\.de/.*?-->\r?\n', '')
    $adminToken = ConvertTo-UnattendPassword 'KITADMINPW'
    $userToken  = ConvertTo-UnattendPassword 'KITUSERPW'
    $expected = [ordered]@{
        'KITADMINDISPLAY' = 1; 'KITUSERDISPLAY' = 1
        '<Name>KITADMIN</Name>' = 1; '<Username>KITADMIN</Username>' = 1; '<Name>KITUSER</Name>' = 1
        '<ComputerName>KIT-HOSTNAME</ComputerName>' = 1; '<TimeZone>UTC</TimeZone>' = 1
        $adminToken = 2; $userToken = 1
    }
    foreach ($token in $expected.Keys) {
        $count = ([regex]::Matches($template, [regex]::Escape($token))).Count
        if ($count -ne $expected[$token]) { Die "media\autounattend.xml: expected $($expected[$token]) of '$token', found $count. Regenerate it with the placeholders (see README)." }
    }

    Write-Info "Passwords for the two accounts Windows Setup will create. They are written only to the install media."
    $adminPw = Read-NewPassword $AdminName
    $userPw  = Read-NewPassword "$UserName (temporary: replaced when you link your Microsoft account)"

    $text = $template.
        Replace('KITADMINDISPLAY', (ConvertTo-XmlText $AdminDisplayName)).
        Replace('KITUSERDISPLAY',  (ConvertTo-XmlText $DisplayName)).
        Replace('<Name>KITADMIN</Name>', "<Name>$(ConvertTo-XmlText $AdminName)</Name>").
        Replace('<Username>KITADMIN</Username>', "<Username>$(ConvertTo-XmlText $AdminName)</Username>").
        Replace('<Name>KITUSER</Name>', "<Name>$(ConvertTo-XmlText $UserName)</Name>").
        Replace('<ComputerName>KIT-HOSTNAME</ComputerName>', "<ComputerName>$HostName</ComputerName>").
        Replace('<TimeZone>UTC</TimeZone>', "<TimeZone>$(ConvertTo-XmlText $TimeZoneId)</TimeZone>").
        Replace($adminToken, (ConvertTo-UnattendPassword $adminPw)).
        Replace($userToken,  (ConvertTo-UnattendPassword $userPw))

    $null = [xml]$text   # must still be well-formed
    [IO.File]::WriteAllText($OutFile, $text, (New-Object Text.UTF8Encoding($false)))
    Write-Info "Answer file written: $OutFile"
}

function Copy-Kit {
    param([Parameter(Mandatory)][string]$Destination)
    robocopy $KitRoot $Destination /E /XD .git redist /XF *.log *-recovery.txt /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { Die "Copying the kit failed (robocopy exit $LASTEXITCODE)." }
    Write-Info "Kit copied to $Destination"
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
$mounted = $null
$stage = $null
try {
    Enter-Elevated -TargetUser $TargetUser -TargetSid $TargetSid -LogPath $LogPath

    # ---------- VM test media: a data ISO with the answer file and the kit ----------
    if ($KitIsoPath) {
        $stage = Join-Path $env:TEMP ("kit-iso-" + [guid]::NewGuid().ToString('N'))
        New-Item $stage -ItemType Directory -Force | Out-Null
        New-AnswerFile -OutFile (Join-Path $stage 'autounattend.xml')
        Copy-Kit -Destination (Join-Path $stage 'windows-setup-scripts')
        if (Test-Path $KitIsoPath) { Remove-Item $KitIsoPath -Force }
        New-DataIso -SourceDir $stage -IsoFile $KitIsoPath
        Write-Info "Test media written: $KitIsoPath (it contains the passwords; delete it when done)."
        Exit-Elevated -Code 0
    }

    # ---------- 1) The ISO ----------
    if (-not $IsoPath) { $IsoPath = Read-Host 'Path to the Windows 11 ISO' }
    $IsoPath = $IsoPath.Trim('"')
    if (-not (Test-Path $IsoPath -PathType Leaf)) { Die "ISO not found: $IsoPath" }
    Write-Info 'Hashing the ISO (about a minute)...'
    $hash = (Get-FileHash $IsoPath -Algorithm SHA256).Hash
    if ($IsoSha256) {
        if ($hash -ne $IsoSha256.Trim().ToUpper()) { Die "ISO hash mismatch.`n  expected $($IsoSha256.ToUpper())`n  actual   $hash" }
        Write-Info 'ISO hash matches.'
    } else {
        Write-Info "ISO SHA-256: $hash"
        Write-Info 'Compare it with "Verify your download" on https://www.microsoft.com/software-download/windows11'
        if ((Read-Host 'Type YES if it matches') -cne 'YES') { Die 'ISO not confirmed; nothing was changed.' }
    }

    # ---------- 2) The USB stick ----------
    $usb = @(Get-Disk | Where-Object { $_.BusType -eq 'USB' })
    if ($usb.Count -eq 0) { Die 'No USB disk found. Plug in the stick and re-run.' }
    $usb | Format-Table Number, FriendlyName, SerialNumber, @{ Label = 'Size (GB)'; Expression = { [math]::Round($_.Size / 1GB, 1) } } -AutoSize | Out-String | Write-Host
    if ($DiskNumber -lt 0) { $DiskNumber = [int](Read-Host 'Disk number of the USB stick to erase') }
    $disk = $usb | Where-Object { $_.Number -eq $DiskNumber }
    if (-not $disk) { Die "Disk $DiskNumber is not a USB disk. Nothing was changed." }
    if ($disk.IsSystem -or $disk.IsBoot) { Die "Disk $DiskNumber holds Windows. Nothing was changed." }
    if ($disk.Size -lt 8GB) { Die "Disk $DiskNumber is smaller than 8 GB." }
    Write-Warn "EVERYTHING on disk $DiskNumber ($($disk.FriendlyName), $([math]::Round($disk.Size / 1GB, 1)) GB) will be erased."
    if ((Read-Host "Type ERASE $DiskNumber to continue") -cne "ERASE $DiskNumber") { Die 'Not confirmed; nothing was changed.' }

    # FAT32 so the stick boots under Secure Boot with only Microsoft's boot manager. Windows
    # formats FAT32 up to 32 GB, so larger sticks get a 30 GB partition.
    $sizeClause = if ($disk.Size -gt 32GB) { ' size=30000' } else { '' }
    $dp = Join-Path $env:TEMP 'kit-diskpart.txt'
    @(
        "select disk $DiskNumber"
        'clean'
        'convert gpt'
        "create partition primary$sizeClause"
        'format fs=fat32 quick label=WINSETUP'
        'assign'
    ) | Set-Content $dp -Encoding ASCII
    diskpart /s $dp | Out-Null
    $dpExit = $LASTEXITCODE
    Remove-Item $dp -Force
    if ($dpExit -ne 0) { Die "diskpart failed (exit $dpExit)." }
    Start-Sleep -Seconds 3
    $letter = (Get-Partition -DiskNumber $DiskNumber | Get-Volume | Where-Object { $_.FileSystemLabel -eq 'WINSETUP' -and $_.DriveLetter }).DriveLetter
    if (-not $letter) { Die 'The new USB volume did not get a drive letter.' }
    $stick = "${letter}:\"
    Write-Info "USB stick formatted: $stick"

    # ---------- 3) ISO contents ----------
    $mounted = Mount-DiskImage -ImagePath (Resolve-Path $IsoPath).Path -PassThru
    $isoRoot = "$(($mounted | Get-Volume).DriveLetter):\"
    Write-Info 'Copying the ISO to the stick (several minutes)...'
    robocopy $isoRoot $stick /E /XF install.wim /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { Die "Copying the ISO failed (robocopy exit $LASTEXITCODE)." }
    $wim = Join-Path $isoRoot 'sources\install.wim'
    if (Test-Path $wim) {
        if ((Get-Item $wim).Length -gt 3800MB) {
            Write-Info 'Splitting install.wim for FAT32 (several minutes)...'
            dism /Split-Image /ImageFile:$wim /SWMFile:"$(Join-Path $stick 'sources\install.swm')" /FileSize:3800 | Out-Null
            if ($LASTEXITCODE -ne 0) { Die "DISM could not split install.wim (exit $LASTEXITCODE)." }
        } else {
            Copy-Item $wim (Join-Path $stick 'sources\install.wim')
        }
    }

    # ---------- 4) Answer file, 5) kit ----------
    New-AnswerFile -OutFile (Join-Path $stick 'autounattend.xml')
    Copy-Kit -Destination (Join-Path $stick 'windows-setup-scripts')

    Write-Info "Install media ready on $stick"
    Write-Info 'Next: update firmware, boot the stick, pick the disk on the Windows Setup screen.'
    Write-Info "After setup, sign in as $UserName and run ${letter}:\windows-setup-scripts\Install.ps1"
} catch {
    Write-Warn "Media build failed: $($_.Exception.Message)"
    $code = 1
} finally {
    if ($mounted) { Dismount-DiskImage -ImagePath $mounted.ImagePath | Out-Null }
    if ($stage -and (Test-Path $stage)) { Remove-Item $stage -Recurse -Force }
}
Exit-Elevated -Code $code
