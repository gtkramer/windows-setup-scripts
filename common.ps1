#Requires -Version 5.1
# Shared configuration and helper functions, dot-sourced by every script.
# Customize this file first when forking.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'   # stop on the first error (fail fast)

# --- Host constants (edit these to fork) -------------------------------------
$HostName       = 'prowsw880acese'            # applied by system\machine.ps1; takes effect after a restart
$TimeZoneId     = 'Pacific Standard Time'     # Windows id for America/Los_Angeles
$GitName        = 'George Kramer'
$GitEmail       = 'george.kramer@live.com'
$GitEditor      = 'vim'                       # the Vim bundled with Git for Windows
$TrustedLanCidr = '192.168.1.0/24'
$SystemDrive    = 'C:'
# MakeMKV's AACS KEYDB.cfg source of truth (copied to %APPDATA%\aacs by makemkv.ps1).
$KeyDbSource    = Join-Path $env:USERPROFILE 'Documents\MakeMKV\KEYDB.cfg'

# --- Kit constants -----------------------------------------------------------
$KitRoot = $PSScriptRoot

# Silence the auto-var lint: these are the fork's public API, consumed by modules.
$null = $HostName, $TimeZoneId, $GitName, $GitEmail, $GitEditor, $TrustedLanCidr,
        $SystemDrive, $KeyDbSource, $KitRoot

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
    if (-not (Test-Admin)) { Die 'This part must run elevated. Start the kit script from a normal (not elevated) terminal; it elevates on its own.' }
}

function Assert-NotAdmin {
    # Per-user work (Store apps, per-user installs, app config) must run unelevated. With
    # Administrator protection on, an elevated process runs in a separate hidden profile, so
    # anything per-user done there would land in the wrong place.
    if (Test-Admin) { Die 'Run this from a normal (not elevated) terminal. It elevates on its own when needed.' }
}

# --- Elevation: one elevated child through Windows' own "run as administrator" prompt ---
function Invoke-Elevated {
    # Launches $ScriptPath elevated in Windows PowerShell 5.1, in its own window, and waits for
    # it. The elevated process may run in a different profile than yours, so it is told which
    # user it is working for. Returns the child's exit code.
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [string[]]$ArgumentList = @()
    )
    $name = [IO.Path]::GetFileNameWithoutExtension($ScriptPath)

    # -ArgumentList is joined with spaces and not quoted for us, so quote the paths here.
    $childArgs = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$ScriptPath`"",
        '-TargetUser', "`"$env:USERNAME`""
    ) + $ArgumentList

    Write-Info "Elevating: $name. Approve the prompt; the elevated part runs in a second window."
    try {
        $proc = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
            -Verb RunAs -PassThru -ArgumentList $childArgs
    } catch {
        Die "Elevation was cancelled or refused: $($_.Exception.Message)"
    }
    $null = $proc.Handle   # keep the handle so ExitCode is readable after exit
    $proc.WaitForExit()    # this process only; installers may leave helpers running
    return $proc.ExitCode
}

function Enter-Elevated {
    # First call in every elevated script: checks the token and records the user it works for.
    param([string]$TargetUser)
    Assert-Admin
    if (-not $TargetUser) { Die 'No target user. Start the kit script from a normal terminal; it elevates on its own.' }
    $global:KitTargetUser = $TargetUser
    Write-Info "Elevated as $env:USERNAME, working for $TargetUser."
}

function Exit-Elevated {
    # Last call in every elevated script. Nothing is logged to disk, so the window stays open
    # until you have read it.
    param([int]$Code = 0)
    $null = Read-Host 'Press Enter to close this window'
    exit $Code
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

function Save-Installer {
    # Downloads a vendor installer over HTTPS to the temp folder and returns its path. The
    # caller runs it and deletes it; nothing is kept in the kit.
    param([Parameter(Mandatory)][string]$Uri)
    if ($Uri -notmatch '^https://') { Die "Refusing a download that is not HTTPS: $Uri" }
    $file = Join-Path $env:TEMP ([IO.Path]::GetFileName(([uri]$Uri).AbsolutePath))
    Write-Info "Downloading $(Split-Path $file -Leaf)..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $prev = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'  # faster IWR
    try   { Invoke-WebRequest -Uri $Uri -OutFile $file -UseBasicParsing }
    finally { $ProgressPreference = $prev }
    return $file
}

function Set-JsonSettings {
    # Merges the values in the kit's $Settings file into the JSON file at $Path, keeping
    # everything else already there, and creates the file when it is missing. The merge runs in
    # PowerShell 7 (user\Merge-JsonSettings.ps1): Windows PowerShell 5.1 cannot read JSON with
    # comments and truncates nested values.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = 'Deliberately plural: merges a set of settings.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Thin wrapper; the merge script reports what it wrote.')]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Settings
    )
    if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
        Write-Warn "PowerShell 7 (pwsh) is not on PATH yet, so $Path was left alone. Open a new terminal and re-run user\Install.ps1."
        return
    }
    pwsh -NoProfile -File (Join-Path $KitRoot 'user\Merge-JsonSettings.ps1') -Path $Path -Settings $Settings
    if ($LASTEXITCODE -ne 0) { Write-Warn "Settings were not merged into $Path (see the message above)." }
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
    # winget is registered per user at first sign-in. The elevated part can run in a profile
    # that has never signed in, so register App Installer for it and re-check.
    if (Get-Command winget -ErrorAction SilentlyContinue) { return }
    try { Add-AppxPackage -RegisterByFamilyName -MainPackage 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe' -ErrorAction Stop }
    catch { Write-Warn "Could not register App Installer for $env:USERNAME`: $($_.Exception.Message)" }
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Die "winget is not available for $env:USERNAME. If this is the elevated window, see the README (Risks: winget under Administrator protection)."
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
