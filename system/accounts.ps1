#Requires -Version 5.1
# The account model: one administrator account, with Windows' Administrator protection on.
# You work without administrator rights; each elevation asks for Windows Hello (or your
# password) and runs in a separate, hidden administrator profile that Windows manages.
. (Join-Path $PSScriptRoot '..\common.ps1')

Assert-Admin

# Administrator protection. This is the value behind the Local Security Policy setting
# "User Account Control: Configure type of Admin Approval Mode" (1 = classic, 2 = with
# Administrator protection). It takes effect after a restart. To turn it off, set it to 1
# and restart, or use Windows Security > Account protection.
Set-RegistryValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'TypeOfAdminApprovalMode' 2

# Windows Setup makes a local account answer three security questions, which can then reset
# the password from the sign-in screen. Turn that reset path off.
Set-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'NoLocalPasswordResetQuestions' 1

Write-Info 'Accounts: Administrator protection on (after a restart); security-question password reset off.'
