# The app lists, grouped by where each app comes from and who installs and updates it.
#
# Sourcing policy, applied in order to every app:
#   1. Microsoft Store, packaged (MSIX)
#   2. Microsoft Store, the vendor's own installer listed by the vendor
#   3. winget, by exact ID, stable releases only
#   4. The vendor's website (see system\tresorit.ps1, user\emby.ps1)
# Two tests at every tier: the publisher is the genuine vendor, and a packaged edition is
# skipped when it lacks something needed.
#
# Re-verify an ID before a rebuild:
#   winget show --id <Id> --source msstore      (publisher + installer host)
#   winget show --id <Id> --exact --source winget
@{
    # Tier 1. Installed by the user; updated by the Store.
    StorePackaged = @(
        '9MZ1SNWT0N5D'   # PowerShell 7           (Microsoft Corporation)
        '9NFNG39387K0'   # Yubico Authenticator   (Yubico AB)
        '9NBLGGH30XJ3'   # Xbox Accessories       (Microsoft Corporation; controller firmware)
    )

    # Tier 1, paid. winget cannot install a paid Store app even when it is owned, so these go
    # through the Store's own command line (or the Store app).
    StorePaid = @(
        '9NGHP3DX8HDX'   # Files                  (Files Community)
    )

    # Tier 2. The vendor's per-user installer; the app updates itself.
    StoreInstaller = @(
        'XP9KHM4BK9FZ7Q' # Visual Studio Code     (Microsoft Corporation)
        'XP89119P9F2PCQ' # Signal                 (Signal Messenger, LLC)
        'XPDC2RH70K22MN' # Discord                (Discord, Inc.)
        'XP99VR1BPSBQJ2' # Epic Games Store       (Epic Games Inc.)
        'XP8JK4HZBVF435' # Auto Dark Mode         (Armin Osaj)
    )

    # Tier 3, per user. Installed and upgraded by the user without elevation.
    WingetUser = @(
        'yt-dlp.yt-dlp'
    )

    # Tier 3, machine-wide. Installed and upgraded by the elevated half.
    WingetMachine = @(
        'Git.Git'
        'Microsoft.DotNet.SDK.10'
        'dotPDN.PaintDotNet'
        'HandBrake.HandBrake'
        'GuinpinSoft.MakeMKV'
        'VideoLAN.VLC'
        'Proton.ProtonVPN'
        'Valve.Steam'
    )

    # Not installed by the kit:
    #   NVIDIA App        winget install --id XP8CLZL93F5Z4P --source msstore   (prompts for elevation)
    #   Microsoft Office  your own purchase; it updates itself
}
