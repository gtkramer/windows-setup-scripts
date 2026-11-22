#Requires -Version 5.1
# User half of Install.ps1: everything that belongs to your own account. Never elevated -
# elevated, these would land in the administrator account's profile.
. (Join-Path $PSScriptRoot '..\common.ps1')

Assert-NotAdmin
Assert-Winget

# Apps the elevated half just installed (git) need a fresh PATH to be visible in this session.
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
            [Environment]::GetEnvironmentVariable('Path', 'User')

Invoke-Modules -BaseDir $PSScriptRoot -Name @(
    'onedrive'   # uninstall the per-user OneDrive client
    'apps'       # Store apps and per-user winget apps
    'git'        # global git identity and defaults
    'vscode'     # VS Code settings.json
    'makemkv'    # AACS KEYDB.cfg
)

Write-Info 'User part complete.'
