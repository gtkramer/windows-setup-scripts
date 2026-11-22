#Requires -Version 5.1
# Set the global git identity and defaults.
. (Join-Path $PSScriptRoot '..\common.ps1')

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Warn 'git is not on PATH yet. Open a new terminal and re-run user\Install.ps1.'
    return
}

git config --global user.name  $GitName
git config --global user.email $GitEmail
git config --global core.editor $GitEditor
git config --global pull.rebase true
git config --global init.defaultBranch main
git config --global core.longpaths true
Write-Info "git identity set: $GitName <$GitEmail> (editor $GitEditor, pull.rebase, init.defaultBranch=main)"
