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
$SystemDrive    = 'C:'
# MakeMKV's AACS KEYDB.cfg source of truth (copied to %APPDATA%\aacs by makemkv.ps1).
$KeyDbSource    = Join-Path $env:USERPROFILE 'Documents\MakeMKV\KEYDB.cfg'

# --- Kit constants -----------------------------------------------------------
$KitRoot = $PSScriptRoot

# Defender attack-surface rules: turned on by system\defender.ps1, checked by
# security\Confirm-Readiness.ps1. Chosen because they do not get in the way of development or
# games. Left out on purpose:
#   01443614-cd74-433a-b99e-2ecdc07bfc25  prevalence, age or trusted list: blocks your own builds
#   5beb7efe-fd9a-4556-801d-275e5ffc04cc  obfuscated scripts: false positives on build scripts
#   c1db55ab-c21a-4637-bb3f-a12568109d35  advanced ransomware protection: same cloud heuristics
#   d1e49aac-8f56-4280-b9ba-993a6d77406c  PSExec and WMI process creation: breaks installers
#   Adobe Reader and web-shell rules: nothing here for them to protect
$AsrRules = [ordered]@{
    '56a863a9-875e-4185-98a7-b882c64b5ce5' = 'Vulnerable signed drivers'
    'e6db77e5-3df2-4cf1-b95a-636979351e5b' = 'Persistence through WMI event subscription'
    'd4f940ab-401b-4efc-aadc-ad5f3c50688a' = 'Office apps creating child processes'
    '3b576869-a4ec-4529-8536-b80a7769e899' = 'Office apps creating executable content'
    '75668c1f-73b5-4cf0-bb93-3ecf5cb7cc84' = 'Office apps injecting code into other processes'
    '92e97fa1-2edf-4476-bdd6-9dd0b4dddc7b' = 'Win32 API calls from Office macros'
    '26190899-1602-49e8-8b27-eb1d0a1ce869' = 'Office communication app creating child processes'
    'be9ba2d9-53ea-4cdc-84e5-9b1eeee46550' = 'Executable content from email and webmail'
    'd3e037e1-3eb8-44c8-a917-57927947596d' = 'JavaScript or VBScript launching downloaded executables'
    'b2b3f03d-6a65-4f7b-a9c7-1c7ef74a9ba4' = 'Unsigned programs run from USB'   # .exe/.dll/.scr, not scripts
    'c0033c00-d16d-4114-a5a0-dc9b3a7d2ceb' = 'Copied or impersonated system tools'
    '33ddedf1-c6e0-47cb-833e-de6133960387' = 'Rebooting into Safe Mode'
    '9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2' = 'Credential stealing from LSASS'
}

# Silence the auto-var lint: these are the fork's public API, consumed by modules.
$null = $HostName, $TimeZoneId, $GitName, $GitEmail, $GitEditor,
        $SystemDrive, $KeyDbSource, $KitRoot, $AsrRules

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
    if ((Get-AdminProtectionState -TargetUser $TargetUser) -eq 'Pending') {
        Write-Warn 'Administrator protection is set but not in effect: this elevated window runs as your own account. Restart the PC; if this warning is still here afterwards, this Windows build is not applying it (see README).'
    }
}

function Get-AdminProtectionState {
    # Call only when elevated. Tells whether Administrator protection is really working, not
    # just configured: with it on, the elevated process runs as a separate account that
    # Windows manages, so its account differs from the user who asked for elevation. With
    # classic User Account Control the two are the same account.
    #   Off      not configured (TypeOfAdminApprovalMode is not 2)
    #   Pending  configured, but this elevated process is still the user's own account
    #   On       configured and elevated as a different account
    #   Unknown  the user could not be looked up as a local account
    param([Parameter(Mandatory)][string]$TargetUser)
    $mode = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'TypeOfAdminApprovalMode'
    if ($mode -ne 2) { return 'Off' }
    try   { $target = (Get-LocalUser -Name $TargetUser -ErrorAction Stop).SID.Value }
    catch { return 'Unknown' }
    if ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -eq $target) { return 'Pending' }
    return 'On'
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

function Remove-RegistryValue {
    # Deletes a value an earlier version of the kit set. Does nothing when it is absent.
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Name)
    if ($null -eq (Get-RegValue $Path $Name)) { return }
    if ($PSCmdlet.ShouldProcess("$Path\$Name", 'remove')) {
        Remove-ItemProperty -Path $Path -Name $Name -Force
    }
}

function Get-AsrRuleState {
    # Returns @{ ruleId = action } for the attack-surface rules Defender has configured
    # (action 1 = block). Empty when none are set.
    $pref  = Get-MpPreference
    $ids   = @($pref.AttackSurfaceReductionRules_Ids)
    $acts  = @($pref.AttackSurfaceReductionRules_Actions)
    $state = @{}
    for ($i = 0; $i -lt $ids.Count; $i++) {
        if ($ids[$i] -and $i -lt $acts.Count) { $state["$($ids[$i])"] = [int]$acts[$i] }
    }
    return $state
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
