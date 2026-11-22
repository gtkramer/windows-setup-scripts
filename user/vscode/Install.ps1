#Requires -Version 5.1
# Merge the checked-in VS Code settings into the user's settings.json. Settings changed in
# VS Code that the kit does not name are kept; the file is created when missing.
. (Join-Path $PSScriptRoot '..\..\common.ps1')

Assert-NotAdmin

Set-JsonSettings -Path (Join-Path $env:APPDATA 'Code\User\settings.json') `
                 -Settings (Join-Path $PSScriptRoot 'settings.json')
