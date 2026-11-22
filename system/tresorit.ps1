#Requires -Version 5.1
# Install Tresorit (end-to-end encrypted sync) from the vendor: it is in neither the Microsoft
# Store nor winget. Idempotent: skips if already present. Tresorit updates itself afterwards.
. (Join-Path $PSScriptRoot '..\common.ps1')

Assert-Admin

if (Test-Path 'C:\Program Files (x86)\Tresorit\Tresorit.exe') {
    Write-Info 'Tresorit already installed.'
    return
}

# Vendor downloads are hash-pinned: download the current installer from
# https://tresorit.com/download into redist\, run `Get-FileHash redist\tresorit_installer.exe
# -Algorithm SHA256`, paste the hash below, commit.
$sha = '<TRESORIT_SHA256>'
if ($sha -like '<*>') {
    Write-Warn 'Pin the Tresorit installer SHA256 in system\tresorit.ps1 before use. Skipping Tresorit.'
    return
}
# Verify this URL/flag against tresorit.com/download before relying on it.
$inst = Get-Redist 'https://installerstorage.blob.core.windows.net/public/install/tresorit_installer.exe' `
                   (Join-Path $KitRoot 'redist\tresorit_installer.exe') $sha
Write-Info 'Installing Tresorit (silent)...'
Start-Process -FilePath $inst -ArgumentList '/S' -Wait
Write-Info 'Tresorit installed.'
