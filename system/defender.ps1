#Requires -Version 5.1
# Microsoft Defender is the only antivirus. Assert it is on and turn on protections that are
# off by default and do not get in the way of development or games: unwanted-app blocking,
# network protection, and the attack-surface rules listed in common.ps1 ($AsrRules). Sample
# submission and tamper protection stay at their defaults.
. (Join-Path $PSScriptRoot '..\common.ps1')

Assert-Admin

try {
    Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction Stop
    Set-MpPreference -PUAProtection Enabled -ErrorAction Stop            # potentially unwanted apps
    Set-MpPreference -EnableNetworkProtection Enabled -ErrorAction Stop  # known-malicious sites, any browser
    $ruleIds = @($AsrRules.Keys)
    Add-MpPreference -AttackSurfaceReductionRules_Ids $ruleIds `
        -AttackSurfaceReductionRules_Actions (@('Enabled') * $ruleIds.Count) -ErrorAction Stop

    # Read the rules back: Defender accepts the call even when a rule does not take.
    $state   = Get-AsrRuleState
    $missing = @($ruleIds | Where-Object { -not $state.ContainsKey($_) -or $state[$_] -ne 1 })
    foreach ($id in $missing) { Write-Warn "Attack-surface rule not enabled: $($AsrRules[$id]) ($id)" }
    Write-Info "Defender: real-time on, unwanted-app blocking, network protection, $($ruleIds.Count - $missing.Count) of $($ruleIds.Count) attack-surface rules."
} catch {
    Write-Warn "Defender settings not fully applied: $($_.Exception.Message)"
}
