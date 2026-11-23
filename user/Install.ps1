#Requires -Version 5.1
# User half of Install.ps1: everything that belongs to your own account. Never elevated -
# elevated, these would land in the wrong profile.
. (Join-Path $PSScriptRoot '..\common.ps1')

Assert-NotAdmin
Assert-Winget

# Apps the elevated half just installed (git) need a fresh PATH to be visible in this session.
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
            [Environment]::GetEnvironmentVariable('Path', 'User')

Invoke-Modules -BaseDir $PSScriptRoot -Name @(
    'onedrive'   # uninstall the per-user OneDrive client
    'apps'       # Store apps and per-user winget apps (PowerShell 7 among them)
    'git'        # global git identity and defaults
    'vscode'     # merge the kit's values into VS Code's settings.json
    'terminal'   # Windows Terminal: longest scrollback
    'makemkv'    # AACS KEYDB.cfg
    'tresorit'   # vendor installer, with its own setup window (last: it waits for you)
)

Write-Info 'User part complete.'
Show-KitWarning   # the elevated part showed its own, in its window
