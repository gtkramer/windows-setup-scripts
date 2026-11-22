#Requires -Version 5.1
<#
.SYNOPSIS
  Run Raphire/Win11Debloat (latest release) with the maintainer's default settings and default
  app-removal list, minus a short list of exceptions and plus a short list of additions.
.DESCRIPTION
  The maintainer keeps each switch current as Windows changes, so the only thing maintained
  here is the three lists below. Every switch name is checked against the release before it
  runs, so a renamed or removed switch fails loudly instead of being skipped.
  Runs at install and whenever Install.ps1 is re-run; never from Update.ps1.
#>
param([switch]$DryRun)   # download, verify and print what would be passed; change nothing
. (Join-Path $PSScriptRoot '..\common.ps1')

if (-not $DryRun) { Assert-Admin }

# --- The kit's deviations from the maintainer's defaults ---------------------
$dropSettings = @(
    'DisableTelemetry'                # disables the telemetry services and Defender sample submission
    'DisableStoreSearchSuggestions'   # works by denying access to a Store database file
)
$addSettings = @(
    'DisableNotepadAI', 'DisablePaintAI', 'DisableEdgeAI'
    'ExplorerToThisPC'                # File Explorer opens to This PC
    'HideSearchTb'                    # no search box or icon on the taskbar
    'TaskbarAlignLeft', 'HideTaskview'
)
$keepApps = @(
    'Microsoft.WindowsAlarms'         # Clock
    'Microsoft.WindowsSoundRecorder'  # Sound Recorder
)
# Never passed, even if they become defaults: gaming, Start pins, Edge removal.
$neverSettings = @(
    'RemoveGamingApps', 'DisableDVR', 'DisableGameBarIntegration'
    'ClearStart', 'ClearStartAllUsers', 'ReplaceStart', 'ReplaceStartAllUsers', 'ForceRemoveEdge'
)

$targetUser = Get-Variable -Name KitTargetUser -Scope Global -ValueOnly -ErrorAction SilentlyContinue
if ($DryRun -and -not $targetUser) { $targetUser = $env:USERNAME }
if (-not $targetUser) { Die 'No target user: this module runs only from an elevated kit script.' }

# --- Download the latest release and verify it against its published checksum ---
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$prevProgress = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
try {
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/Raphire/Win11Debloat/releases/latest' -UseBasicParsing
    $zipAsset = $release.assets | Where-Object { $_.name -eq 'Win11Debloat.zip' }
    $sumAsset = $release.assets | Where-Object { $_.name -eq 'SHA256SUMS' }
    if (-not $zipAsset -or -not $sumAsset) { throw 'the release has no Win11Debloat.zip or SHA256SUMS asset.' }

    # The administrator's temp folder: not writable by the standard account.
    $work = Join-Path $env:TEMP "Win11Debloat-$($release.tag_name)"
    if (Test-Path $work) { Remove-Item $work -Recurse -Force }
    New-Item $work -ItemType Directory -Force | Out-Null
    $zip  = Join-Path $work 'Win11Debloat.zip'
    $sums = Join-Path $work 'SHA256SUMS'
    Invoke-WebRequest -Uri $zipAsset.browser_download_url -OutFile $zip  -UseBasicParsing
    Invoke-WebRequest -Uri $sumAsset.browser_download_url -OutFile $sums -UseBasicParsing
} catch {
    Write-Warn "Win11Debloat could not be downloaded; skipping it this run. $($_.Exception.Message)"
    return
} finally { $ProgressPreference = $prevProgress }

$sumLine = Get-Content $sums | Where-Object { $_ -match '^\s*([0-9a-fA-F]{64})\s+\*?Win11Debloat\.zip\s*$' } | Select-Object -First 1
if (-not $sumLine) { Die 'SHA256SUMS has no entry for Win11Debloat.zip.' }
$expected = ($sumLine.Trim() -split '\s+')[0]
$actual   = (Get-FileHash $zip -Algorithm SHA256).Hash
if ($actual -ne $expected.ToUpper()) { Die "Win11Debloat.zip does not match its published checksum.`n  expected $expected`n  actual   $actual" }

$src = Join-Path $work 'src'
Expand-Archive -Path $zip -DestinationPath $src -Force
$script = Get-ChildItem $src -Recurse -Filter 'Win11Debloat.ps1' | Select-Object -First 1
if (-not $script) { Die 'Win11Debloat.ps1 not found in the release archive.' }
$toolRoot     = $script.DirectoryName
$settingsFile = Join-Path $toolRoot 'Config\DefaultSettings.json'
$appsFile     = Join-Path $toolRoot 'Config\Apps.json'
foreach ($f in $settingsFile, $appsFile) {
    if (-not (Test-Path $f)) { Die "Win11Debloat's layout changed: $f is missing. Update system\debloat.ps1." }
}
Write-Info "Win11Debloat $($release.tag_name) verified."

# --- Maintainer's default settings, minus drops, plus additions --------------
$defaults = @((Get-Content $settingsFile -Raw | ConvertFrom-Json).Settings | Where-Object { $_.Value -ne $false })
if ($defaults.Count -eq 0) { Die "Win11Debloat's DefaultSettings.json has no settings. Update system\debloat.ps1." }

$settings = [ordered]@{}
foreach ($d in $defaults) { $settings[$d.Name] = $d.Value }
foreach ($name in $dropSettings + $neverSettings) { $settings.Remove($name) }
foreach ($name in $addSettings) { $settings[$name] = $true }

# Passed as an explicit switch, this one skips the tool's own "is Modern Standby present" check.
if ($settings.Contains('DisableModernStandbyNetworking')) {
    $available = ((powercfg /a | Out-String) -split 'not available')[0]
    if ($available -notmatch 'S0 Low Power Idle') { $settings.Remove('DisableModernStandbyNetworking') }
}

# Defaults that do not apply to this Windows build (the tool lists a build range per setting).
$featuresFile = Join-Path $toolRoot 'Config\Features.json'
if (Test-Path $featuresFile) {
    $build = [Environment]::OSVersion.Version.Build
    foreach ($feature in (Get-Content $featuresFile -Raw | ConvertFrom-Json).Features) {
        $id  = $feature.PSObject.Properties['FeatureId']
        $min = $feature.PSObject.Properties['MinVersion']
        $max = $feature.PSObject.Properties['MaxVersion']
        if (-not $id -or -not $settings.Contains($id.Value)) { continue }
        if (($min -and $min.Value -and $build -lt $min.Value) -or ($max -and $max.Value -and $build -gt $max.Value)) {
            $settings.Remove($id.Value)
        }
    }
}

# Every name must still be a parameter of this release.
$known = (Get-Command $script.FullName).Parameters.Keys
foreach ($name in $addSettings) {
    if ($name -notin $known) { Die "Win11Debloat no longer has -$name. Update the lists in system\debloat.ps1." }
}
foreach ($name in @($settings.Keys)) {
    if ($name -notin $known) {
        Write-Warn "Win11Debloat default '$name' is not a switch in this release; skipped."
        $settings.Remove($name)
    }
}

# --- Maintainer's default app-removal list, minus the apps to keep -----------
$removeApps = @((Get-Content $appsFile -Raw | ConvertFrom-Json).Apps |
    Where-Object { $_.SelectedByDefault } |
    ForEach-Object { $_.AppId } |          # AppId is a string or a list of strings
    Where-Object { $_ -notin $keepApps } |
    Select-Object -Unique)
if ($removeApps.Count -eq 0) { Die "Win11Debloat's Apps.json yielded no default apps. Update system\debloat.ps1." }

# --- Run it against the daily user's profile ---------------------------------
$toolArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script.FullName,
              '-Silent', '-User', $targetUser, '-LogPath', $KitLogDir)
foreach ($name in $settings.Keys) {
    $toolArgs += "-$name"
    if ($settings[$name] -isnot [bool]) { $toolArgs += "$($settings[$name])" }
}
$toolArgs += @('-RemoveApps', '-Apps', ($removeApps -join ','))

Write-Info "Settings: $($settings.Keys -join ', ')"
Write-Info "Removing $($removeApps.Count) default apps (keeping: $($keepApps -join ', '))."

if ($DryRun) {
    Write-Info "Dry run. Apps that would be removed: $($removeApps -join ', ')"
    Write-Info 'Nothing was changed.'
    return
}

$toolLog = Join-Path $KitLogDir 'Win11Debloat.log'
$logStart = if (Test-Path $toolLog) { (Get-Item $toolLog).Length } else { 0 }

& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" @toolArgs
if ($LASTEXITCODE -ne 0) { Die "Win11Debloat exited with $LASTEXITCODE. See $toolLog." }

# The tool exits 0 even when individual changes fail; surface those lines from its log.
if (Test-Path $toolLog) {
    $stream = [IO.File]::Open($toolLog, 'Open', 'Read', 'ReadWrite')
    try {
        $null = $stream.Seek($logStart, 'Begin')
        $newText = (New-Object IO.StreamReader($stream)).ReadToEnd()
    } finally { $stream.Dispose() }
    $newText -split "`r?`n" | Where-Object { $_ -match 'failed|Skipping|not supported' } |
        ForEach-Object { Write-Warn "Win11Debloat: $($_.Trim())" }
}

Write-Info "Win11Debloat applied to $targetUser. Sign out and back in for the shell settings to show."
