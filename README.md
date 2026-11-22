# Windows Setup Scripts

A version-controlled PowerShell kit that installs and maintains a lean **Windows 11 Pro**
gaming and development workstation: one constants file to edit, one install script that elevates
when it needs to, one update script.

Host: `prowsw880acese` (ASUS Pro WS W880-ACE SE, RTX 5080, firmware TPM).

The guiding rule is to **work with how Microsoft designs and services Windows 11**, not against
it: documented answer-file settings, policies that Pro honors, supported app removal, Windows
Update left to run itself. Nothing strips components or replaces Windows Setup.

> **Honest scope.** The kit reproduces most of a fresh machine. Activation, the Microsoft account
> link, the NVIDIA driver, Edge's own settings, Microsoft Office and your files are finished by
> hand (step 6 below). The recovery path is *rebuild from these scripts*, not restore an image.

---

## What you get

| Area | Choice |
|---|---|
| Windows Update | Left to Windows: stable updates install automatically, no release pin. One policy: never restart while you are signed in, so you are prompted |
| Accounts | You sign in as `george`, a **standard user** linked to your Microsoft account. `ad_george` is a separate local administrator used only for elevation and as break-glass. The built-in Administrator stays disabled |
| Bloat, ads, AI | [Win11Debloat](https://github.com/Raphire/Win11Debloat), latest release: the maintainer's defaults with a short exception list ([system/debloat.ps1](system/debloat.ps1)) |
| Shell | Built-in settings only: extensions shown, Explorer opens to This PC, taskbar left with search and Task View hidden. Theme is left to Auto Dark Mode |
| Telemetry | Supported policies only. Pro's floor is "Required"; nothing is disabled by force |
| Security | Microsoft Defender with three extra protections, plus six settings from Microsoft's security baseline ([system/hardening.ps1](system/hardening.ps1)) |
| Encryption | BitLocker, XTS-AES-256, TPM + PIN. The recovery key is written where you choose and never uploaded |
| Apps | Microsoft Store first, then winget, then the vendor ([apps.psd1](apps.psd1)) |
| Browser | Microsoft Edge, signed in |

## Layout

```
windows-setup-scripts/
|-- common.ps1                 # constants + helpers - CUSTOMIZE THIS FIRST
|-- apps.psd1                  # the app lists, by source and scope
|-- Install.ps1                # converge this PC: elevated system part, then your user part
|-- Update.ps1                 # upgrade the winget apps
|-- media/
|   |-- New-InstallMedia.ps1   # build the install USB (or a kit ISO for VM testing)
|   `-- autounattend.xml       # answer file, generated, with placeholders
|-- system/                    # ELEVATED: machine-wide state
|   |-- Install.ps1, Update.ps1
|   `-- policy, hardening, defender, onedrive, developer, apps, tresorit, debloat
|-- user/                      # AS YOU: your own account
|   |-- Install.ps1
|   `-- onedrive, apps, git, vscode/, makemkv   (standalone: emby)
|-- security/
|   |-- Enable-BitLocker.ps1   # TPM + PIN, XTS-AES-256, recovery key to a folder you choose
|   `-- Confirm-Readiness.ps1  # read-only report
|-- test/New-TestVm.ps1        # Hyper-V VM for rehearsing the install
`-- redist/                    # downloaded vendor installers (gitignored)
```

**Conventions.** Every script dot-sources `common.ps1`. A module is `Foo.ps1` or
`Foo/Install.ps1`; add one by dropping a script in and appending its name to the list in the
folder's `Install.ps1`. Modules are safe to re-run.

**Customize first:** the constants at the top of [common.ps1](common.ps1) (`$UserName`,
`$DisplayName`, `$HostName`, `$TimeZoneId`, `$GitEmail`, `$TrustedLanCidr`). The administrator
account is always named `ad_` plus `$UserName`.

## How elevation works

You run every script as your standard account. When a script needs administrator rights it
starts **one elevated child** through Windows' own "run as administrator" prompt and you type
the `ad_george` password. No `sudo`, no add-ons.

- The elevated child runs as `ad_george`, with that account's profile. So machine-wide work
  lives in `system/`, and anything that belongs to your account (Store apps, per-user installs,
  git and VS Code settings) lives in `user/` and is never elevated.
- The elevated child's output is mirrored into your window and logged under
  `C:\ProgramData\windows-setup-scripts\logs`.
- The kit runs from wherever you keep it (the USB at first, then your clone). **The password
  vouches for whatever is in that folder at that moment**, so keep the clone free of changes you
  did not make.

---

## Install runbook

1. **Edit [common.ps1](common.ps1).** Back up your files. You need a Windows 11 Pro license;
   this is a clean install.
2. **Build the USB** on any Windows PC:
   ```powershell
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
   .\media\New-InstallMedia.ps1 -IsoPath <Win11 ISO> -IsoSha256 <hash from Microsoft>
   ```
   Download the multi-edition x64 ISO from <https://www.microsoft.com/software-download/windows11>.
   The script erases the stick you choose (after you type a confirmation), copies the ISO, asks
   for the two account passwords, and writes the answer file and the kit to the stick.
3. **Firmware.** Update the BIOS. Secure Boot **on**, firmware TPM **on**.
4. **Boot the stick and pick the disk** on Windows Setup's screen. Disconnect data disks if you
   want no chance of choosing the wrong one. Everything else is unattended: edition, locale,
   hostname, both accounts, and the one-time settings in the table below. Setup signs in to
   `ad_george` once by itself to delete its cached answer files. **Sign out of `ad_george`.**
5. **Sign in as `george`.** Link your Microsoft account (Settings > Accounts > Your info >
   "Sign in with a Microsoft account instead"). Then:
   ```powershell
   D:\windows-setup-scripts\Install.ps1      # the stick's drive letter; one elevation prompt
   ```
   Sign out and back in afterwards so the shell settings show.
6. **Finish by hand:**
   - NVIDIA App and driver: `winget install --id XP8CLZL93F5Z4P --source msstore`
   - Encryption: `.\security\Enable-BitLocker.ps1`, then restart, enter the PIN, and move the
     recovery key file to offline storage
   - Activate Windows with your Pro key
   - Edge: sign in, then turn off its ad and AI features (see below)
   - Microsoft Office, then restore your files
   - Check: `.\security\Confirm-Readiness.ps1`
7. **Keep the kit:** `git clone` it into your profile and run `Update.ps1` from there.

### What the answer file sets, once

[media/autounattend.xml](media/autounattend.xml) is generated by
[Christoph Schneegans' generator](https://schneegans.de/windows/unattend-generator/). Windows
Setup's own installer does the disk and image work.

| Setting | Value |
|---|---|
| Edition, language | Windows 11 Pro (generic key selects the edition; it does not activate), en-US |
| Computer name, time zone | From `common.ps1` |
| Accounts | `ad_george` (Administrators), `george` (Users); passwords never expire |
| PowerShell scripts | Allowed (RemoteSigned) |
| File system | Long paths on; 8.3 short names off for new files |
| Power, clock | Fast Startup off; hardware clock in UTC |
| Privacy questions | All declined |
| Encryption | Windows' own automatic encryption prevented; policy set to XTS-AES-256 with a PIN allowed |

An answer file is processed once and never re-applied, so only one-time setup lives there.
Everything that may need re-applying lives in `Install.ps1`.

**Regenerating it.** The file's first comment is the generator URL with placeholder names and
passwords (`KITADMIN`, `KITUSER`, `KIT-HOSTNAME`, `KITADMINPW`, ...), so no personal details are
sent to the site. Open that URL, change options, choose "View .xml file", and save the result
over `media/autounattend.xml`. `New-InstallMedia.ps1` substitutes the real values and stops if
the placeholders are not where it expects them.

### Edge, by hand

Microsoft does not apply most Edge ad and AI policies to a profile signed in with a Microsoft
account. After signing in, turn these off once in `edge://settings` (they sync with your
account): the Copilot button and sidebar, shopping and rewards, new-tab-page content and feed,
"personalization & advertising". The kit still sets the Edge policies that do apply.

---

## Keeping it current

```powershell
.\Update.ps1
```

| Updated by | What |
|---|---|
| `Update.ps1`, no elevation | Per-user winget apps |
| `Update.ps1`, one elevation, only when something is out of date | Machine-wide winget apps |
| Windows itself | Windows Update, Defender signatures, Store apps |
| The app itself | VS Code, Signal, Discord, Epic, Auto Dark Mode, NVIDIA App, Steam, Tresorit, Office |

Windows installs updates automatically and then **waits for you** to restart; restarts ask for
the BitLocker PIN. Having that one update policy means Windows holds some new monthly features
until the yearly release and shows a "managed" note on the update page.

**Re-applying policies and the debloat tool:** re-run `Install.ps1`, for example after the yearly
Windows release. It runs the then-latest Win11Debloat; to see what it would pass without
changing anything: `.\system\debloat.ps1 -DryRun`.

## Apps

The sourcing policy, applied in order to every app:

1. **Microsoft Store, packaged (MSIX)** - clean install and removal, updated by the Store.
2. **Microsoft Store, the vendor's own installer** listed by the vendor.
3. **winget**, by exact ID, stable releases only.
4. **The vendor's website**, hash-pinned in the kit.

At every tier the publisher must be the genuine vendor (the Store's "HandBrake", for instance,
is a paid look-alike), and a packaged edition is skipped when it lacks something needed (the
Store's sandboxed VLC cannot play discs). The lists are in [apps.psd1](apps.psd1). Everything on
winget is there because the Store has no genuine or adequate edition, except Paint.NET, where
the developer's free installer was chosen over the paid Store edition.

Vendor downloads ([system/tresorit.ps1](system/tresorit.ps1), [user/emby.ps1](user/emby.ps1))
skip until you pin the installer's SHA256 in the script: download once, `Get-FileHash <file>
-Algorithm SHA256`, paste, commit.

## Rehearsing in a VM

Rehearse before touching the real PC. On a host with Hyper-V enabled
(`Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All`, then restart):

```powershell
.\media\New-InstallMedia.ps1 -KitIsoPath C:\iso\kit.iso          # answer file + kit as a data ISO
.\test\New-TestVm.ps1 -WinIso C:\iso\Win11.iso -KitIso C:\iso\kit.iso
```

The VM cannot reproduce the graphics card's effect on BitLocker, and an unactivated Windows
greys out the Personalization pages.

---

## Risks and gotchas

1. **BitLocker and firmware changes.** A BIOS update, a BIOS settings change or a GPU firmware
   update makes BitLocker ask for the recovery key at the next boot. Suspend it first:
   `manage-bde -protectors -disable C: -RebootCount 1`. Keep the recovery key reachable offline.
2. **The install stick holds the account passwords** in reversible form until `Install.ps1`
   deletes the answer file from it. A kit ISO made for VM testing holds them too.
3. **Microsoft account link.** Converting a local account has open failure reports on 26H2. If it
   fails, set a new local password and retry; failing that, add your Microsoft account as a new
   standard user from `ad_george`.
4. **Standard-user friction.** Elevated tools run as `ad_george` with a different profile (no
   git config, no SSH keys, a different PATH). SDK workloads, WSL setup, drivers and anti-cheat
   installs prompt for the password. `george` is in Hyper-V Administrators and Developer Mode is
   on, which removes the most common prompts.
5. **Win11Debloat** has one main maintainer and is not code-signed; the kit runs whatever was
   last released, checked only against that release's own checksum.
6. **IDs drift.** Re-verify before a rebuild: `winget show --id <Id> --source msstore` (publisher
   and installer host) or `winget show --id <Id> --exact --source winget`.
7. **Not yet proven on real hardware.** The scripts were written against research on Windows 11
   Pro 26H2, not run end to end. Rehearse in the VM first; the points most worth confirming are
   listed in the plan's verification section.

## References

- Windows 11 release information: <https://learn.microsoft.com/en-us/windows/release-health/windows11-release-information>
- Answer files: <https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/windows-setup-automation-overview>
- BitLocker countermeasures: <https://learn.microsoft.com/en-us/windows/security/operating-system-security/data-protection/bitlocker/countermeasures>
- Security baselines: <https://learn.microsoft.com/en-us/windows/security/operating-system-security/device-management/windows-security-configuration-framework/windows-security-baselines>
- WinGet: <https://learn.microsoft.com/en-us/windows/package-manager/winget/>
