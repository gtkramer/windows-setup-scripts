#Requires -Version 5.1
# Store apps and per-user winget apps, from apps.psd1. Installed by you without elevation.
# Store-packaged apps are then updated by the Store; apps installed from the Store with their
# vendor's installer update themselves; Update.ps1 upgrades the per-user winget apps.
. (Join-Path $PSScriptRoot '..\common.ps1')

Assert-NotAdmin
Assert-Winget
$apps = Get-AppList

Install-WingetPackage -Id $apps.StorePackaged  -Source msstore
Install-WingetPackage -Id $apps.StoreInstaller -Source msstore
Install-WingetPackage -Id $apps.WingetUser     -Source winget -Scope user

# Paid Store apps: winget cannot install them even when they are owned. Use the Store's own
# command line where it exists, otherwise open the Store page.
foreach ($id in $apps.StorePaid) {
    # winget's exit code does not say whether it is installed; look for the app's row.
    $listed = winget list --id $id --source msstore --disable-interactivity --accept-source-agreements | Out-String
    if ($listed -match "(?m)\s$([regex]::Escape($id))\s") { Write-Info "Store app $id already installed."; continue }
    if (Get-Command store -ErrorAction SilentlyContinue) {
        Write-Info "store install $id"
        store install $id
        if ($LASTEXITCODE -eq 0) { continue }
        Write-Warn "store install $id exited with $LASTEXITCODE."
    }
    Write-Warn "Install $id from the Store page that is opening (you must be signed in to the Store)."
    Start-Process "ms-windows-store://pdp/?ProductId=$id"
}

Write-Info 'User apps requested.'
