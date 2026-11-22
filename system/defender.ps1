#Requires -Version 5.1
# Microsoft Defender is the only antivirus. Assert it is on and turn on three protections that
# are off by default and do not get in the way of development or games. Sample submission and
# tamper protection stay at their defaults.
. (Join-Path $PSScriptRoot '..\common.ps1')

Assert-Admin

# Attack-surface rules chosen for low friction:
$asrRules = @(
    '56a863a9-875e-4185-98a7-b882c64b5ce5'   # block abuse of exploited vulnerable signed drivers
    'e6db77e5-3df2-4cf1-b95a-636979351e5b'   # block persistence through WMI event subscription
)

try {
    Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction Stop
    Set-MpPreference -PUAProtection Enabled -ErrorAction Stop            # potentially unwanted apps
    Set-MpPreference -EnableNetworkProtection Enabled -ErrorAction Stop  # known-malicious sites, any browser
    $asrActions = @('Enabled') * $asrRules.Count
    Add-MpPreference -AttackSurfaceReductionRules_Ids $asrRules `
        -AttackSurfaceReductionRules_Actions $asrActions -ErrorAction Stop
    Write-Info 'Defender: real-time on, unwanted-app blocking, network protection, 2 attack-surface rules.'
} catch {
    Write-Warn "Defender settings not fully applied: $($_.Exception.Message)"
}
