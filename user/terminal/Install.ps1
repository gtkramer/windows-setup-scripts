#Requires -Version 5.1
# Give Windows Terminal its longest scrollback. The kit keeps no log files, so the console
# history is the record of a run.
. (Join-Path $PSScriptRoot '..\..\common.ps1')

Assert-NotAdmin

$state = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState'
if (-not (Test-Path $state)) {
    Write-Info 'Windows Terminal is not installed for this account; skipped.'
    return
}
Set-JsonSettings -Path (Join-Path $state 'settings.json') -Settings (Join-Path $PSScriptRoot 'settings.json')
