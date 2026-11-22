#Requires -Version 5.1
# Set the global git identity and defaults.
. (Join-Path $PSScriptRoot '..\common.ps1')

Assert-NotAdmin

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
# Check symbolic links out as real links. Needs Developer Mode (system\machine.ps1), which lets
# a non-elevated process create them. Repositories cloned before this need a fresh checkout.
git config --global core.symlinks true
Write-Info "git identity set: $GitName <$GitEmail> (editor $GitEditor, pull.rebase, init.defaultBranch=main, symlinks)"
