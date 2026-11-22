#Requires -Version 5.1
# Install Tresorit (end-to-end encrypted sync) from the vendor: it is in neither the Microsoft
# Store nor winget. Runs as you, with the vendor's own setup window; the installer asks for
# elevation itself if it needs it. Tresorit updates itself afterwards.
. (Join-Path $PSScriptRoot '..\common.ps1')

Assert-NotAdmin

$installed = @(
    (Join-Path $env:LOCALAPPDATA 'Tresorit')
    (Join-Path ${env:ProgramFiles(x86)} 'Tresorit')
    (Join-Path $env:ProgramFiles 'Tresorit')
) | Where-Object { Get-ChildItem $_ -Recurse -Filter 'Tresorit.exe' -ErrorAction SilentlyContinue | Select-Object -First 1 }
if ($installed) {
    Write-Info 'Tresorit already installed.'
    return
}

$inst = Save-Installer 'https://installer.tresorit.com/Tresorit.exe'
try {
    Write-Info 'Starting the Tresorit installer. Follow its window.'
    Start-Process -FilePath $inst -Wait
} finally {
    Remove-Item $inst -Force -ErrorAction SilentlyContinue
}
Write-Info 'Tresorit installer finished.'
