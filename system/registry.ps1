#Requires -Version 5.1
# Write the kit's registry settings: every value in the Apply group of system\registry.psd1
# (Administrator protection, privacy and update policies, Edge, hardening, OneDrive, Developer
# Mode). The reason for each value is beside it in that file. Safe to re-run;
# security\Confirm-Readiness.ps1 checks against the same table.
. (Join-Path $PSScriptRoot '..\common.ps1')

Assert-Admin

Set-KitRegistry -Group Apply

$counts = @(Get-KitRegistry -Group Apply) | Group-Object Area | ForEach-Object { "$($_.Name) $($_.Count)" }
Write-Info "Registry settings applied ($($counts -join ', '))."
Write-Info 'Administrator protection takes effect after a restart.'
