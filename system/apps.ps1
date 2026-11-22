#Requires -Version 5.1
# Machine-wide winget apps: the ones with no genuine or adequate Microsoft Store edition.
# The list is apps.psd1 (WingetMachine). Idempotent: winget skips what is already installed.
. (Join-Path $PSScriptRoot '..\common.ps1')

Assert-Admin
Assert-Winget

Install-WingetPackage -Id (Get-AppList).WingetMachine -Source winget -Scope machine

Write-Info 'Machine-wide apps requested.'
