#Requires -Version 5.1
# Shared configuration and helper functions, dot-sourced by every script.
# Customize this file first when forking.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'   # stop on the first error (fail fast)

# --- Host constants (edit these to fork) -------------------------------------
$UserName         = 'george'                   # daily account: standard user, Microsoft account
$DisplayName      = 'George Kramer'
$AdminName        = "ad_$UserName"             # local administrator: elevation + break-glass
$AdminDisplayName = "$DisplayName (admin)"
$GitName          = $DisplayName
$GitEmail         = 'george.kramer@live.com'
$GitEditor        = 'vim'                      # the Vim bundled with Git for Windows
$TimeZoneId       = 'Pacific Standard Time'    # Windows id for America/Los_Angeles
$HostName         = 'prowsw880acese'
$TrustedLanCidr   = '192.168.1.0/24'
$SystemDrive      = 'C:'
# MakeMKV's AACS KEYDB.cfg source of truth (copied to %APPDATA%\aacs by makemkv.ps1).
$KeyDbSource      = Join-Path $env:USERPROFILE 'Documents\MakeMKV\KEYDB.cfg'

# --- Kit constants -----------------------------------------------------------
$KitRoot   = $PSScriptRoot
$KitLogDir = Join-Path $env:ProgramData 'windows-setup-scripts\logs'

# Silence the auto-var lint: these are the fork's public API, consumed by modules.
$null = $UserName, $DisplayName, $AdminName, $AdminDisplayName, $GitName, $GitEmail,
        $GitEditor, $TimeZoneId, $HostName, $TrustedLanCidr, $SystemDrive, $KeyDbSource,
        $KitRoot, $KitLogDir

# --- Error + privilege helpers ----------------------------------------------
function Write-Info {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Interactive provisioning status; console output is intentional.')]
    param([string]$Message)
    Write-Host "INFO: $Message" -ForegroundColor Cyan
}
function Write-Warn { param([string]$Message) Write-Warning $Message }
function Die        { param([string]$Message) throw "ERROR: $Message" }

function Test-Admin {
    # True when this process holds an elevated administrator token.
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

function Assert-Admin {
    if (-not (Test-Admin)) { Die 'This part must run elevated. Start the kit script as yourself; it elevates on its own.' }
}

function Assert-NotAdmin {
    # Per-user work (Store apps, per-user installs, app config) must run as the daily user:
    # elevated, it would land in the administrator account's profile.
    if (Test-Admin) { Die "Run this as your standard account ($UserName), not elevated. It elevates on its own when needed." }
}

# --- Elevation: one elevated child through Windows' own "run as administrator" prompt ---
function Invoke-Elevated {
    # Launches $ScriptPath elevated in Windows PowerShell 5.1 and waits for it. The child runs as
    # the administrator whose credentials are typed at the prompt, so it is told which user it
    # is working for. Its transcript is mirrored into this window. Returns the child's exit code.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Mirrors the elevated transcript to the console.')]
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [string[]]$ArgumentList = @()
    )
    if (-not (Test-Path $KitLogDir)) { New-Item $KitLogDir -ItemType Directory -Force | Out-Null }
    $name = [IO.Path]::GetFileNameWithoutExtension($ScriptPath)
    $log  = Join-Path $KitLogDir ('{0}-{1:yyyyMMdd-HHmmss}.log' -f $name, (Get-Date))
    $sid  = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value

    # -ArgumentList is joined with spaces and not quoted for us, so quote the paths here.
    $childArgs = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$ScriptPath`"",
        '-TargetUser', "`"$env:USERNAME`"", '-TargetSid', $sid, '-LogPath', "`"$log`""
    ) + $ArgumentList

    Write-Info "Elevating: $name (enter the $AdminName password at the prompt)"
    try {
        $proc = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
            -Verb RunAs -PassThru -ArgumentList $childArgs
    } catch [ComponentModel.Win32Exception] {
        Die "Elevation was cancelled or refused: $($_.Exception.Message)"
    }
    $null = $proc.Handle   # keep the handle so ExitCode is readable after exit

    $position = 0L
    do {
        $done = $proc.HasExited
        if (Test-Path $log) {
            $stream = [IO.File]::Open($log, 'Open', 'Read', 'ReadWrite')
            try {
                $null   = $stream.Seek($position, 'Begin')
                $reader = New-Object IO.StreamReader($stream)
                $text   = $reader.ReadToEnd()
                $position = $stream.Position
                if ($text) { Write-Host $text -NoNewline }
            } finally { $stream.Dispose() }
        }
        if (-not $done) { Start-Sleep -Milliseconds 500 }
    } until ($done)

    Write-Info "Elevated log: $log"
    return $proc.ExitCode
}

function Enter-Elevated {
    # First call in every elevated script. Checks the token, checks that the target user the
    # unelevated half named really is that account, and starts the transcript the parent mirrors.
    param([string]$TargetUser, [string]$TargetSid, [string]$LogPath)
    Assert-Admin
    if ($TargetSid -notmatch '^S-1-5-21-\d+-\d+-\d+-\d+$') { Die "Target account id is missing or malformed: '$TargetSid'" }
    try {
        $account = ([Security.Principal.SecurityIdentifier]$TargetSid).Translate([Security.Principal.NTAccount]).Value
    } catch { Die "Target account id $TargetSid does not resolve to an account on this PC." }
    if (($account -split '\\')[-1] -ne $TargetUser) { Die "Target account id resolves to $account, not $TargetUser." }
    if ($LogPath) { Start-Transcript -Path $LogPath -Append | Out-Null }
    $global:KitTargetUser = $TargetUser
    $global:KitTargetSid  = $TargetSid
    Write-Info "Elevated as $env:USERNAME, working for $TargetUser."
}

function Exit-Elevated {
    # Last call in every elevated script: stop the transcript and return the exit code.
    param([int]$Code = 0)
    try { Stop-Transcript | Out-Null } catch { $null = $_ }
    exit $Code
}

function Get-TargetUserKey {
    # Registry path of the daily user's hive as seen from the elevated child, where HKCU is
    # the administrator's hive. The hive is loaded while that user is signed in.
    param([Parameter(Mandatory)][string]$SubKey)
    $sid = Get-Variable -Name KitTargetSid -Scope Global -ValueOnly -ErrorAction SilentlyContinue
    if (-not $sid) { Die 'No target user: this module runs only from an elevated kit script.' }
    $root = "Registry::HKEY_USERS\$sid"
    if (-not (Test-Path $root)) { Die "The profile of the target user is not loaded (is that account signed in?)." }
    return "$root\$SubKey"
}

# --- Idempotent primitives ---------------------------------------------------
function Set-RegistryValue {
    # New-Item guard + New-ItemProperty -Force overwrite = idempotent; re-running is safe.
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [Microsoft.Win32.RegistryValueKind]$Type = [Microsoft.Win32.RegistryValueKind]::DWord
    )
    if ($PSCmdlet.ShouldProcess("$Path\$Name", "set to $Value")) {
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
    }
}

function Get-RegValue {
    # Strict-mode-safe read: returns $null if the key or value is absent.
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Name)
    try { return (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name }
    catch { return $null }
}

function Get-Redist {
    # Download + SHA256 verify. Skips the download if the file already exists; verifies the
    # hash every run when one is given.
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$OutFile,
        [string]$Sha256
    )
    $dir = Split-Path $OutFile
    if ($dir -and -not (Test-Path $dir)) { New-Item $dir -ItemType Directory -Force | Out-Null }
    if (-not (Test-Path $OutFile)) {
        Write-Info "Downloading $(Split-Path $OutFile -Leaf)..."
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $prev = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'  # faster IWR
        try   { Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing }
        finally { $ProgressPreference = $prev }
    }
    if ($Sha256) {
        $actual = (Get-FileHash $OutFile -Algorithm SHA256).Hash
        if ($actual -ne $Sha256.ToUpper()) {
            Remove-Item $OutFile -Force -ErrorAction SilentlyContinue
            Die "Hash mismatch for $OutFile`n  expected $($Sha256.ToUpper())`n  actual   $actual"
        }
    }
    return $OutFile
}

# --- Package wrappers --------------------------------------------------------
$WingetNoApplicableInstaller = -1978335216   # 0x8A150010
$WingetNoUpgradeAvailable    = -1978335189   # 0x8A15002B
$null = $WingetNoApplicableInstaller, $WingetNoUpgradeAvailable

function Get-AppList {
    # The app lists live in apps.psd1, grouped by source and scope.
    return Import-PowerShellDataFile -Path (Join-Path $KitRoot 'apps.psd1')
}

function Assert-Winget {
    # winget is registered per user at first sign-in. For an account that has barely signed in
    # (the administrator), register App Installer for it and re-check.
    if (Get-Command winget -ErrorAction SilentlyContinue) { return }
    try { Add-AppxPackage -RegisterByFamilyName -MainPackage 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe' -ErrorAction Stop }
    catch { Write-Warn "Could not register App Installer for $env:USERNAME`: $($_.Exception.Message)" }
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Die "winget is not available for $env:USERNAME. Sign in to that account once, let the Store update App Installer, and re-run."
    }
}

function Install-WingetPackage {
    # winget is idempotent by id; --exact avoids ambiguous matches. Every call names its source:
    # 'winget' for the community repository, 'msstore' for the Microsoft Store.
    param(
        [Parameter(Mandatory)][string[]]$Id,
        [Parameter(Mandatory)][ValidateSet('winget', 'msstore')][string]$Source,
        [ValidateSet('user', 'machine')][string]$Scope
    )
    $common = @('--source', $Source, '--silent', '--accept-source-agreements',
                '--accept-package-agreements', '--disable-interactivity')
    foreach ($pkg in $Id) {
        $idArgs = if ($Source -eq 'winget') { @('--exact', '--id', $pkg) } else { @('--id', $pkg) }
        $scopeArgs = if ($Scope) { @('--scope', $Scope) } else { @() }
        Write-Info "winget install $pkg ($Source$(if ($Scope) { ", $Scope" }))"
        winget install @idArgs @scopeArgs @common
        if ($LASTEXITCODE -eq $WingetNoApplicableInstaller -and $Scope) {
            # Some manifests declare no scope; retry without the filter.
            winget install @idArgs @common
        }
        # Non-zero also means "already installed / nothing newer": a success for a re-run.
        if ($LASTEXITCODE -ne 0) { Write-Warn "winget exit $LASTEXITCODE for $pkg (already installed?)." }
    }
}

function Test-WingetUpgrade {
    # True when winget reports a newer version for an installed package. Read-only.
    # winget exits 0 whether or not an upgrade exists, so look for the package's row: with
    # --upgrade-available it is listed only when there is something to upgrade to.
    param([Parameter(Mandatory)][string]$Id)
    $out = winget list --id $Id --exact --source winget --upgrade-available --disable-interactivity --accept-source-agreements | Out-String
    return ($out -match "(?m)\s$([regex]::Escape($Id))\s")
}

function Update-WingetPackage {
    param(
        [Parameter(Mandatory)][string[]]$Id,
        [ValidateSet('user', 'machine')][string]$Scope
    )
    foreach ($pkg in $Id) {
        if (-not (Test-WingetUpgrade $pkg)) { continue }
        $scopeArgs = if ($Scope) { @('--scope', $Scope) } else { @() }
        Write-Info "winget upgrade $pkg"
        winget upgrade --exact --id $pkg --source winget @scopeArgs --silent `
            --accept-source-agreements --accept-package-agreements --disable-interactivity
        if ($LASTEXITCODE -eq $WingetNoApplicableInstaller -and $Scope) {
            winget upgrade --exact --id $pkg --source winget --silent `
                --accept-source-agreements --accept-package-agreements --disable-interactivity
        }
        if ($LASTEXITCODE -ne 0) { Write-Warn "winget exit $LASTEXITCODE upgrading $pkg." }
    }
}

# --- The module dispatcher: Foo.ps1 OR Foo/Install.ps1 ----------------------
function Invoke-Modules {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = 'Deliberately plural: runs a set of modules.')]
    param(
        [Parameter(Mandatory)][string]$BaseDir,
        [Parameter(Mandatory)][string[]]$Name
    )
    foreach ($module in $Name) {
        $script = Join-Path $BaseDir "$module.ps1"
        if (-not (Test-Path $script)) { $script = Join-Path $BaseDir "$module\Install.ps1" }
        if (-not (Test-Path $script)) {
            Die "Module not found: $module (looked for $module.ps1 and $module\Install.ps1)"
        }
        Write-Info "-- $module"
        & $script
    }
}
