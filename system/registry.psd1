# Every registry value the kit sets or relies on, in one place. Install.ps1 and the BitLocker
# scripts write from this table, and security\Confirm-Readiness.ps1 checks against it, so the
# two cannot drift apart.
#
#   Apply      written by system\registry.ps1 on every Install.ps1 run
#   BitLocker  written by security\bitlocker.ps1 when a drive is first encrypted
#   Expect     never written from here: the answer file, fsutil or Windows sets these. Checked only
#
# One entry per registry key: Area (the report's group), Path, and Values. Each value has a Name,
# a Value and a Check (the line the report prints). A Value is a number, stored as a DWORD;
# $null means the value must be absent, and it is removed when present.
#
# To add a setting, add a line here: nothing else needs to change. Only values Windows 11 Pro
# honors belong here, under a Policies key where one exists so Windows updates leave them alone.
@{
    Apply = @(
        # --- Machine ---
        # Developer Mode: a non-elevated process may create symbolic links (git needs this).
        @{ Area = 'Machine'; Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'; Values = @(
            @{ Name = 'AllowDevelopmentWithoutDevLicense'; Value = 1; Check = 'Developer Mode (symbolic links)' }
        ) }
        # Earlier versions of the kit kept the hardware clock in UTC, for dual booting with Linux.
        # This PC does not dual boot, so the clock is back at the Windows default (local time).
        @{ Area = 'Machine'; Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation'; Values = @(
            @{ Name = 'RealTimeIsUniversal'; Value = $null; Check = 'Hardware clock in local time (Windows default)' }
        ) }

        # --- Accounts: one administrator account, with Windows' Administrator protection on ---
        # You work without administrator rights; each elevation asks for Windows Hello (or your
        # password) and runs in a separate, hidden administrator profile that Windows manages.
        # This is the value behind the Local Security Policy setting "User Account Control:
        # Configure type of Admin Approval Mode" (1 = classic, 2 = with Administrator protection).
        # It takes effect after a restart. To turn it off, set it to 1 and restart, or use
        # Windows Security > Account protection.
        @{ Area = 'Accounts'; Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Values = @(
            @{ Name = 'TypeOfAdminApprovalMode'; Value = 2; Check = 'Administrator protection configured' }
        ) }
        # Windows Setup makes a local account answer three security questions, which can then
        # reset the password from the sign-in screen. Turn that reset path off.
        @{ Area = 'Accounts'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Values = @(
            @{ Name = 'NoLocalPasswordResetQuestions'; Value = 1; Check = 'Security-question password reset off' }
        ) }

        # --- Privacy. Diagnostic data: Pro's floor is Required (1); level 0 is Enterprise-only ---
        @{ Area = 'Policy'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Values = @(
            @{ Name = 'AllowTelemetry';                 Value = 1; Check = 'Diagnostic data = Required' }
            @{ Name = 'LimitDiagnosticLogCollection';   Value = 1; Check = 'Diagnostic log collection limited' }
            @{ Name = 'LimitDumpCollection';            Value = 1; Check = 'Dump collection limited' }
            @{ Name = 'DoNotShowFeedbackNotifications'; Value = 1; Check = 'Feedback notifications off' }
        ) }
        @{ Area = 'Policy'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo'; Values = @(
            @{ Name = 'DisabledByGroupPolicy'; Value = 1; Check = 'Advertising ID off' }
        ) }
        # Location services: left at the Windows default.

        # --- Windows Update: updates arrive as on any Windows 11 PC; the restart is yours for 2 days ---
        # Monthly updates are not held back: they install as soon as Microsoft releases them,
        # because attackers start studying a fix the day it is published. The one thing the kit
        # changes is the restart. Windows does not restart by itself for 2 days after installing;
        # when they end it restarts whether or not you are signed in, after a 15-minute warning.
        # The policy counts in whole days. Everything else stays at its defaults (stable updates
        # only, no pin); the yearly feature update and driver updates restart the way Windows
        # normally does. Having any update policy makes Windows hold some new monthly features
        # until the yearly release.
        @{ Area = 'Updates'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'; Values = @(
            @{ Name = 'SetComplianceDeadlineForQU';                     Value = 1; Check = 'Restart deadline policy on' }
            @{ Name = 'ConfigureDeadlineForQualityUpdates';             Value = 0; Check = 'Updates install as soon as offered' }
            @{ Name = 'ConfigureDeadlineGracePeriod';                   Value = 2; Check = 'Restart within 2 days of installing' }
            @{ Name = 'ConfigureDeadlineNoAutoRebootForQualityUpdates'; Value = 1; Check = 'No automatic restart before then' }
            # No waiting period before updates are offered (an earlier draft of the kit set one).
            @{ Name = 'DeferQualityUpdates';             Value = $null; Check = 'Monthly updates not held back' }
            @{ Name = 'DeferQualityUpdatesPeriodInDays'; Value = $null; Check = 'No waiting period after release' }
        ) }
        @{ Area = 'Updates'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'; Values = @(
            # "Receive updates for other Microsoft products": .NET, Office and Visual Studio are
            # then updated by Windows Update too. This is the value in Windows' own policy
            # definition (WindowsUpdate.admx, "Configure Automatic Updates").
            @{ Name = 'AllowMUUpdateService'; Value = 1; Check = 'Updates for other Microsoft products on' }
            # Earlier versions of the kit set these. The deadline policy overrides the first, and
            # Microsoft's guidance is not to use the second on Windows 11.
            @{ Name = 'AUOptions';                     Value = $null; Check = 'Old update option removed' }
            @{ Name = 'NoAutoRebootWithLoggedOnUsers'; Value = $null; Check = 'Old no-restart option removed' }
        ) }
        # "Notify me when a restart is required" (Settings > Windows Update > Advanced options):
        # show the restart notice when the restart becomes pending, not when the deadline arrives.
        @{ Area = 'Updates'; Path = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'; Values = @(
            @{ Name = 'RestartNotificationsAllowed2'; Value = 1; Check = 'Restart notice shown when pending' }
        ) }

        # --- Edge: telemetry and security. Its ad and AI policies come from the debloat tool ---
        # Microsoft does not apply most Edge ad/AI policies to a profile signed in with a
        # Microsoft account; those are turned off once by hand in Edge's settings (see README).
        @{ Area = 'Edge'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'; Values = @(
            @{ Name = 'DiagnosticData';                  Value = 0; Check = 'Diagnostic data off' }
            @{ Name = 'PersonalizationReportingEnabled'; Value = 0; Check = 'Personalization reporting off' }
            @{ Name = 'EnhanceSecurityMode';             Value = 1; Check = 'Enhanced security mode (balanced)' }   # extra exploit protection on unfamiliar sites
            @{ Name = 'PasswordManagerEnabled';          Value = 0; Check = 'Built-in password saving off' }        # passwords live in the password manager
            # Earlier versions of the kit set these two. Edge honors them only on a PC that is
            # domain-joined or enrolled in device management, so here they did nothing.
            # SmartScreen is on by default; its unwanted-app blocking is turned on by hand (README).
            @{ Name = 'SmartScreenEnabled';    Value = $null; Check = 'Ignored SmartScreen policy removed' }
            @{ Name = 'SmartScreenPuaEnabled'; Value = $null; Check = 'Ignored unwanted-app policy removed' }
        ) }

        # --- Hardening: five settings from Microsoft's Windows 11 security baseline ---
        # The ones that are safe on an unmanaged home PC and are not already the Windows default.
        # The baseline as a whole is NOT applied: it disables the Xbox services and sleep, and
        # blocks unsigned local builds. All five are reversible.
        # 1) Legacy LLMNR name lookups off (spoofable on untrusted networks). mDNS stays on.
        # 2) NetBIOS name lookups off, on every network (same spoofing as LLMNR; the baseline
        #    turns them off on public networks only). This is name resolution: adapters still
        #    list "NetBIOS over Tcpip" as enabled, a separate per-adapter setting left alone.
        @{ Area = 'Hardening'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'; Values = @(
            @{ Name = 'EnableMulticast'; Value = 0; Check = 'LLMNR name lookups off' }
            @{ Name = 'EnableNetbios';   Value = 0; Check = 'NetBIOS name lookups off' }
        ) }
        # 3) AutoPlay / AutoRun off for all drive types.
        @{ Area = 'Hardening'; Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'; Values = @(
            @{ Name = 'NoDriveTypeAutoRun'; Value = 255; Check = 'AutoPlay off for all drive types' }
            @{ Name = 'NoAutorun';          Value = 1;   Check = 'AutoRun off' }
        ) }
        # 4) No anonymous enumeration of accounts and shares.
        @{ Area = 'Hardening'; Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'; Values = @(
            @{ Name = 'RestrictAnonymous'; Value = 1; Check = 'No anonymous enumeration' }
        ) }
        # 5) Remote Assistance invitations off.
        @{ Area = 'Hardening'; Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance'; Values = @(
            @{ Name = 'fAllowToGetHelp'; Value = 0; Check = 'Remote Assistance off' }
        ) }

        # --- OneDrive: blocked by policy so it does not sync or come back ---
        # OneDrive installs per user, so the uninstall itself is done by user\onedrive.ps1.
        @{ Area = 'OneDrive'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive'; Values = @(
            @{ Name = 'DisableFileSyncNGSC'; Value = 1; Check = 'OneDrive sync blocked' }
        ) }
    )

    # XTS-AES-256 for every drive type (7), and a startup PIN allowed (2 = allow). Must be in
    # place before a drive is encrypted: the cipher cannot be changed on an encrypted drive.
    BitLocker = @(
        @{ Area = 'Encryption'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\FVE'; Values = @(
            @{ Name = 'EncryptionMethodWithXtsOs';  Value = 7; Check = 'Cipher policy: system drive XTS-AES-256' }
            @{ Name = 'EncryptionMethodWithXtsFdv'; Value = 7; Check = 'Cipher policy: internal drives XTS-AES-256' }
            @{ Name = 'EncryptionMethodWithXtsRdv'; Value = 7; Check = 'Cipher policy: removable drives XTS-AES-256' }
            @{ Name = 'UseAdvancedStartup';         Value = 1; Check = 'Startup policy: extra sign-in at startup configured' }
            @{ Name = 'EnableBDEWithNoTPM';         Value = 0; Check = 'Startup policy: no BitLocker without a TPM' }
            @{ Name = 'UseTPM';                     Value = 2; Check = 'Startup policy: TPM allowed' }
            @{ Name = 'UseTPMPIN';                  Value = 2; Check = 'Startup policy: TPM + PIN allowed' }
            @{ Name = 'UseTPMKey';                  Value = 2; Check = 'Startup policy: TPM + startup key allowed' }
            @{ Name = 'UseTPMKeyPIN';               Value = 2; Check = 'Startup policy: TPM + key + PIN allowed' }
        ) }
    )

    Expect = @(
        # Set once by media\autounattend.xml, during Windows Setup.
        @{ Area = 'Answer file'; Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'; Values = @(
            @{ Name = 'LongPathsEnabled'; Value = 1; Check = 'Long paths enabled' }
        ) }
        @{ Area = 'Answer file'; Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'; Values = @(
            @{ Name = 'HiberbootEnabled'; Value = 0; Check = 'Fast Startup off' }
        ) }
        @{ Area = 'Answer file'; Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\BitLocker'; Values = @(
            @{ Name = 'PreventDeviceEncryption'; Value = 1; Check = 'Automatic device encryption prevented' }
        ) }
        # Set by system\machine.ps1 through fsutil, which is the supported way to change it.
        @{ Area = 'Machine'; Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'; Values = @(
            @{ Name = 'NtfsDisable8dot3NameCreation'; Value = 1; Check = '8.3 names off for new files' }
        ) }
        # Windows defaults the kit relies on and does not set.
        @{ Area = 'Windows defaults'; Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Values = @(
            @{ Name = 'EnableLUA'; Value = 1; Check = 'User Account Control on' }
        ) }
        @{ Area = 'Windows defaults'; Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'; Values = @(
            @{ Name = 'fDenyTSConnections'; Value = 1; Check = 'Remote Desktop off' }
        ) }
    )
}
