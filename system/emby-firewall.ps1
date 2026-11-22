#Requires -Version 5.1
# Elevated half of user\emby.ps1: allow Emby (8096/tcp) inbound from the trusted LAN only.
param([string]$TargetUser)
. (Join-Path $PSScriptRoot '..\common.ps1')

$code = 0
try {
    Enter-Elevated -TargetUser $TargetUser
    if (-not (Get-NetFirewallRule -DisplayName 'Emby Server (LAN)' -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName 'Emby Server (LAN)' -Direction Inbound -Action Allow `
            -Protocol TCP -LocalPort 8096 -RemoteAddress $TrustedLanCidr | Out-Null
    }
    Write-Info "Emby is reachable from $TrustedLanCidr only."
} catch {
    Write-Warn "Firewall rule failed: $($_.Exception.Message)"
    $code = 1
}
Exit-Elevated -Code $code
