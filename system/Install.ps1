#Requires -Version 5.1
# Elevated half of Install.ps1. Launched by it through Invoke-Elevated; not run by hand.
# Machine-wide state only. Anything per-user belongs in user\Install.ps1.
param([string]$TargetUser)
. (Join-Path $PSScriptRoot '..\common.ps1')

$code = 0
try {
    Enter-Elevated -TargetUser $TargetUser
    Assert-Winget
    Invoke-Modules -BaseDir $PSScriptRoot -Name @(
        'machine'     # computer name, time zone, UTC clock, 8.3 names, Developer Mode
        'accounts'    # Administrator protection, no security-question password reset
        'policy'      # telemetry, Windows Update restart, Edge
        'hardening'   # four settings from Microsoft's security baseline
        'defender'    # Defender on, plus low-friction extras
        'onedrive'    # block OneDrive by policy (the user half uninstalls it)
        'apps'        # machine-wide winget apps
        'debloat'     # Win11Debloat: maintainer's defaults minus the kit's exceptions (last: it
                      # depends on a download, and must not hold up the modules above)
    )
    Write-Info 'System part complete.'
} catch {
    Write-Warn "System part failed: $($_.Exception.Message)"
    $code = 1
}
Exit-Elevated -Code $code
