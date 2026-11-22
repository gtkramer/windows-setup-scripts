#Requires -Version 5.1
# Privacy and update policies. Only values Windows 11 Pro honors, written under the Policies
# keys so Windows updates leave them alone. Idempotent via Set-RegistryValue.
. (Join-Path $PSScriptRoot '..\common.ps1')

Assert-Admin

# --- Diagnostic data. Pro's floor is Required (1); level 0 is Enterprise-only. ---
$dc = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
Set-RegistryValue $dc 'AllowTelemetry' 1
Set-RegistryValue $dc 'LimitDiagnosticLogCollection' 1
Set-RegistryValue $dc 'LimitDumpCollection' 1
Set-RegistryValue $dc 'DoNotShowFeedbackNotifications' 1

# --- Advertising ID ---
Set-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo' 'DisabledByGroupPolicy' 1

# --- Windows Update: updates arrive as on any Windows 11 PC; the restart is yours for 2 days. ---
# Monthly updates are not held back: they install as soon as Microsoft releases them, because
# attackers start studying a fix the day it is published. The one thing the kit changes is the
# restart. Windows does not restart by itself for 2 days after installing; when they end it
# restarts whether or not you are signed in, after a 15-minute warning. The policy counts in
# whole days.
# Everything else about Windows Update stays at its defaults (stable updates only, no pin);
# the yearly feature update and driver updates restart the way Windows normally does.
# Having any update policy makes Windows hold some new monthly features until the yearly release.
$wu = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
Set-RegistryValue $wu 'SetComplianceDeadlineForQU' 1
Set-RegistryValue $wu 'ConfigureDeadlineForQualityUpdates' 0               # install as soon as offered
Set-RegistryValue $wu 'ConfigureDeadlineGracePeriod' 2                     # then 2 days to restart
Set-RegistryValue $wu 'ConfigureDeadlineNoAutoRebootForQualityUpdates' 1   # no restart before those days are up
# No waiting period before updates are offered (an earlier draft of the kit set one).
Remove-RegistryValue $wu 'DeferQualityUpdates'
Remove-RegistryValue $wu 'DeferQualityUpdatesPeriodInDays'
# Earlier versions of the kit set these. The deadline policy overrides the first, and
# Microsoft's guidance is not to use the second on Windows 11.
Remove-RegistryValue "$wu\AU" 'AUOptions'
Remove-RegistryValue "$wu\AU" 'NoAutoRebootWithLoggedOnUsers'
# "Notify me when a restart is required" (Settings > Windows Update > Advanced options): show
# the restart notice when the restart becomes pending, not when the deadline arrives.
Set-RegistryValue 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings' 'RestartNotificationsAllowed2' 1

# --- Edge: telemetry and security policies. Its ad and AI policies come from the debloat tool. ---
# Microsoft does not apply most Edge ad/AI policies to a profile signed in with a Microsoft
# account; those are turned off once by hand in Edge's settings (see README).
$edge = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
Set-RegistryValue $edge 'DiagnosticData' 0
Set-RegistryValue $edge 'PersonalizationReportingEnabled' 0
Set-RegistryValue $edge 'EnhanceSecurityMode' 1      # balanced: extra exploit protection on unfamiliar sites
Set-RegistryValue $edge 'PasswordManagerEnabled' 0   # passwords live in the password manager, not in Edge
# Microsoft documents these two as honored only on domain-joined or managed PCs. SmartScreen
# is on by default either way; edge://policy shows whether Edge accepted them (see README).
Set-RegistryValue $edge 'SmartScreenEnabled' 1
Set-RegistryValue $edge 'SmartScreenPuaEnabled' 1    # block downloads of potentially unwanted apps

# Location services: left at the Windows default.

Write-Info 'Policies applied (diagnostic data Required, ad id off, updates on release with a 2-day restart deadline, Edge security).'
