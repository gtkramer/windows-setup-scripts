#Requires -Version 5.1
# Copy the checked-in VS Code settings.json into the user's Code profile.
. (Join-Path $PSScriptRoot '..\..\common.ps1')

$dest = Join-Path $env:APPDATA 'Code\User'
if (-not (Test-Path $dest)) { New-Item $dest -ItemType Directory -Force | Out-Null }
Copy-Item -Force (Join-Path $PSScriptRoot 'settings.json') (Join-Path $dest 'settings.json')
Write-Info "VS Code settings.json installed to $dest"
