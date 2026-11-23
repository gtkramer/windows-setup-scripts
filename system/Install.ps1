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
        'machine'     # computer name, time zone, 8.3 names
        'registry'    # every registry setting, from registry.psd1: Administrator protection,
                      # privacy, Windows Update, Edge, hardening, OneDrive, Developer Mode
        'defender'    # Defender on, plus low-friction extras and attack-surface rules
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
