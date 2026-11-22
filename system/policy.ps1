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

# --- Windows Update: install automatically, never restart while someone is signed in. ---
# Everything else about Windows Update stays at its defaults (stable updates only, no pin).
# Having any update policy makes Windows hold some new monthly features until the yearly release.
$au = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
Set-RegistryValue $au 'AUOptions' 4                       # download and install automatically
Set-RegistryValue $au 'NoAutoRebootWithLoggedOnUsers' 1   # prompt for the restart instead

# --- Edge: the telemetry policies. Its ad and AI policies come from the debloat tool. ---
# Microsoft does not apply most Edge ad/AI policies to a profile signed in with a Microsoft
# account; those are turned off once by hand in Edge's settings (see README).
$edge = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
Set-RegistryValue $edge 'DiagnosticData' 0
Set-RegistryValue $edge 'PersonalizationReportingEnabled' 0

# Location services: left at the Windows default.

Write-Info 'Policies applied (diagnostic data Required, ad id off, restart on your say-so).'
