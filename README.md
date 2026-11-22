# Windows Setup Scripts

A version-controlled PowerShell kit that installs and maintains a lean **Windows 11 Pro**
gaming and development workstation: one constants file to edit, one install script that elevates
when it needs to, one update script.

Host: `prowsw880acese` (ASUS Pro WS W880-ACE SE, RTX 5080, firmware TPM).

The guiding rule is to **work with how Microsoft designs and services Windows 11**, not against
it: documented answer-file settings, policies that Pro honors, supported app removal, Windows
Update left to run itself. Nothing strips components or replaces Windows Setup. The aim is a Pro
install that behaves like the LTSC edition: it installs the way Windows 7 did and then stays quiet.

> **Honest scope.** The kit reproduces most of a fresh machine. Activation, the Windows Hello PIN,
> app sign-ins, the NVIDIA driver, Edge's own settings, Microsoft Office and your files are
> finished by hand (step 6 below). The recovery path is *rebuild from these scripts*, not restore
> an image.

---

## What you get

| Area | Choice |
|---|---|
| Windows Update | Left to Windows: stable updates install automatically, no release pin. One policy: never restart while you are signed in, so you are prompted |
| Accounts | One **local administrator account**, created by Windows Setup asking for a name and password. **Administrator protection** is on: you work without administrator rights and approve each elevation with Windows Hello. The built-in Administrator stays disabled. Your Microsoft account is signed in per app, not to Windows |
| Bloat, ads, AI | [Win11Debloat](https://github.com/Raphire/Win11Debloat), latest release: the maintainer's defaults with a short exception list ([system/debloat.ps1](system/debloat.ps1)) |
| Shell | Built-in settings only: extensions shown, Explorer opens to This PC, taskbar left with search and Task View hidden. Theme is left to Auto Dark Mode |
| Telemetry | Supported policies only. Pro's floor is "Required"; nothing is disabled by force |
| Security | Microsoft Defender with three extra protections, plus four settings from Microsoft's security baseline ([system/hardening.ps1](system/hardening.ps1)) |
| Encryption | BitLocker, XTS-AES-256, TPM + PIN. The recovery key is shown once for your password manager; it is never written to a file or uploaded |
| Apps | Microsoft Store first, then winget, then the vendor ([apps.psd1](apps.psd1)) |
| Browser | Microsoft Edge, signed in |

## Layout

```
windows-setup-scripts/
|-- common.ps1                 # constants + helpers - CUSTOMIZE THIS FIRST
|-- apps.psd1                  # the app lists, by source and scope
|-- Install.ps1                # converge this PC: elevated system part, then your user part
|-- Update.ps1                 # upgrade the winget apps
|-- media/autounattend.xml     # answer file, generated; holds no names and no passwords
|-- system/                    # ELEVATED: machine-wide state
|   |-- Install.ps1, Update.ps1
|   `-- machine, accounts, policy, hardening, defender, onedrive, apps, debloat
|-- user/                      # AS YOU: your own account
|   |-- Install.ps1
|   |-- onedrive, apps, git, vscode/, terminal/, makemkv, tresorit   (standalone: emby)
|   `-- Merge-JsonSettings.ps1 # helper (PowerShell 7): merge values into a JSON settings file
|-- security/
|   |-- Enable-BitLocker.ps1   # TPM + PIN, XTS-AES-256, recovery key shown for your password manager
|   `-- Confirm-Readiness.ps1  # read-only report
`-- test/New-TestVm.ps1        # Hyper-V VM for rehearsing the install
```

**Conventions.** Every script dot-sources `common.ps1`. A module is `Foo.ps1` or
`Foo/Install.ps1`; add one by dropping a script in and appending its name to the list in the
folder's `Install.ps1`. Modules are safe to re-run. The kit targets Windows PowerShell 5.1, which
every Windows install has; only the JSON merge uses PowerShell 7, which the kit installs first.

**Customize first:** the constants at the top of [common.ps1](common.ps1) (`$HostName`,
`$TimeZoneId`, `$GitName`, `$GitEmail`, `$TrustedLanCidr`).

## How elevation works

You run every script from a normal terminal. When a script needs administrator rights it starts
**one elevated child** through Windows' own "run as administrator" prompt. No `sudo`, no add-ons.

- With Administrator protection on, the prompt asks for Windows Hello (PIN or fingerprint) or
  your password. On the very first run, before the restart that turns it on, it is the ordinary
  Yes/No prompt.
- The elevated child runs in its own window and, under Administrator protection, in a separate
  hidden administrator profile that Windows manages. So machine-wide work lives in `system/`, and
  anything that belongs to your account (Store apps, per-user installs, git and VS Code settings)
  lives in `user/` and is never elevated.
- **Nothing is logged to disk.** The elevated window waits for Enter before it closes so you can
  read it. Win11Debloat keeps its own log in the elevated profile.
- The kit runs from wherever you keep it (the USB at first, then your clone). **Your approval
  vouches for whatever is in that folder at that moment**, so keep the clone free of changes you
  did not make.

---

## Install runbook

1. **Edit [common.ps1](common.ps1).** Back up your files. You need a Windows 11 Pro license;
   this is a clean install.
2. **Build the USB** on any Windows PC with Microsoft's Media Creation Tool, from
   <https://www.microsoft.com/software-download/windows11> ("Create Windows 11 Installation
   Media"). Then add the answer file and the kit (replace `E:` with the stick's letter):
   ```powershell
   Copy-Item .\media\autounattend.xml E:\
   robocopy . E:\windows-setup-scripts /E /XD .git
   ```
   The stick holds no names and no passwords.
3. **Firmware.** Update the BIOS. Secure Boot **on**, firmware TPM **on**.
4. **Boot the stick and pick the disk** on Windows Setup's screen. Disconnect data disks if you
   want no chance of choosing the wrong one. Setup then asks for **your account name and
   password**, and three security questions: give throwaway answers, the kit turns that reset
   path off. Everything else is unattended: edition, locale, and the settings in the table below.
5. **Sign in** and run the kit from the stick:
   ```powershell
   D:\windows-setup-scripts\Install.ps1      # the stick's drive letter; one elevation prompt
   ```
   **Restart** afterwards: the computer name, Administrator protection and the shell settings
   need it.
6. **Finish by hand:**
   - Windows Hello PIN: Settings > Accounts > Sign-in options. Elevation prompts use it
   - NVIDIA App and driver: `winget install --id XP8CLZL93F5Z4P --source msstore`
   - Encryption: `.\security\Enable-BitLocker.ps1`. Save the recovery key it shows in your
     password manager, then restart and enter the PIN
   - Activate Windows with your Pro key
   - Sign in to the Store, Edge and Office with your Microsoft account. When Windows offers to
     use the account everywhere, choose **"Microsoft apps only"** so the Windows account stays local
   - Edge: turn off its ad and AI features (see below)
   - Microsoft Office, then restore your files
   - Check: `.\security\Confirm-Readiness.ps1`
7. **Keep the kit:** `git clone` it into your profile and run `Update.ps1` from there.

### What the answer file sets, once

[media/autounattend.xml](media/autounattend.xml) is generated by
[Christoph Schneegans' generator](https://schneegans.de/windows/unattend-generator/) and uses
only its built-in options. Windows Setup's own installer does the disk and image work.

| Setting | Value |
|---|---|
| Edition, language | Windows 11 Pro (generic key selects the edition; it does not activate), en-US |
| Account | Asked by Setup: one local account, no Microsoft account screens; passwords never expire |
| PowerShell scripts | Allowed (RemoteSigned) |
| File system | Long paths on |
| Power | Fast Startup off |
| Privacy questions | All declined |
| Encryption | Windows' own automatic encryption prevented, so `Enable-BitLocker.ps1` starts from a clean drive |

An answer file is processed once and never re-applied, so only what must be in place before the
first sign-in lives there. Everything else lives in `Install.ps1`, including the computer name,
time zone, UTC hardware clock and 8.3 short names ([system/machine.ps1](system/machine.ps1)).
Until that first run the PC has a random name.

**Regenerating it.** The file's first comment is the generator URL that produced it. Open that
URL, change options, choose "View .xml file", and save the result over `media/autounattend.xml`.
It contains no personal details.

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
| The app itself | VS Code, Signal, Discord, Epic, Auto Dark Mode, Bing Wallpaper, NVIDIA App, Steam, Tresorit, Office |

Windows installs updates automatically and then **waits for you** to restart; restarts ask for
the BitLocker PIN. Having that one update policy means Windows holds some new monthly features
until the yearly release and shows a "managed" note on the update page.

**Re-applying policies and the debloat tool:** re-run `Install.ps1`, for example after the yearly
Windows release. It runs the then-latest Win11Debloat, which removes the maintainer's default app
list again: an app on that list that you installed since is removed unless it is in `$keepApps`
in [system/debloat.ps1](system/debloat.ps1). To see what it would do without changing anything:
`.\system\debloat.ps1 -DryRun`.

**Settings files.** The VS Code and Windows Terminal modules merge the kit's values into your
existing `settings.json` and leave everything else alone. Comments in those files are not kept.

## Apps

The sourcing policy, applied in order to every app:

1. **Microsoft Store, packaged (MSIX)** - clean install and removal, updated by the Store.
2. **Microsoft Store, the vendor's own installer** listed by the vendor.
3. **winget**, by exact ID, stable releases only.
4. **The vendor's website**, over HTTPS from the vendor's own download address.

At every tier the publisher must be the genuine vendor (the Store's "HandBrake", for instance,
is a paid look-alike), and a packaged edition is skipped when it lacks something needed (the
Store's sandboxed VLC cannot play discs). The lists are in [apps.psd1](apps.psd1). Everything on
winget is there because the Store has no genuine or adequate edition, except Paint.NET, where
the developer's free installer was chosen over the paid Store edition.

Vendor downloads ([user/tresorit.ps1](user/tresorit.ps1), [user/emby.ps1](user/emby.ps1)) are
fetched to the temp folder, run with the vendor's own setup window, and deleted. Nothing is kept
in the kit.

## Rehearsing in a VM

Rehearse before touching the real PC. On a host with Hyper-V enabled
(`Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All`, then restart):

```powershell
.\test\New-TestVm.ps1 -WinIso C:\iso\Win11.iso      # the Media Creation Tool can save an ISO
```

It packs the answer file and the kit into a small ISO and attaches it as a second DVD. The VM
cannot reproduce the graphics card's effect on BitLocker, and an unactivated Windows greys out
the Personalization pages.

---

## Risks and gotchas

1. **BitLocker and firmware changes.** A BIOS update, a BIOS settings change or a GPU firmware
   update makes BitLocker ask for the recovery key at the next boot. Suspend it first:
   `manage-bde -protectors -disable C: -RebootCount 1`. The recovery key exists only where you
   saved it.
2. **Administrator protection is new** (2026) and has changed since release.
   - Microsoft says not to enable it on PCs that require Hyper-V. To run Hyper-V VMs, turn it
     off first and restart: Windows Security > Account protection, or set
     `TypeOfAdminApprovalMode` to `1` (see [system/accounts.ps1](system/accounts.ps1)).
     `Install.ps1` turns it back on.
   - **winget under Administrator protection.** The elevated part runs in a profile that has
     never signed in. The kit registers winget there; if the elevated window still reports that
     winget is not available, turn Administrator protection off, restart, run the script, and
     turn it back on.
   - With one account there is no second administrator. If the account is locked out, recovery
     is through the Windows recovery environment, which needs the BitLocker recovery key.
3. **Elevated tools run in a different profile**: no git config, no SSH keys, a different PATH.
   SDK workloads, WSL setup, drivers and anti-cheat installs prompt for elevation. Developer Mode
   is on, so symbolic links work without elevation.
4. **Win11Debloat** has one main maintainer and is not code-signed; the kit runs whatever was
   last released, checked only against that release's own checksum.
5. **IDs drift.** Re-verify before a rebuild: `winget show --id <Id> --source msstore` (publisher
   and installer host) or `winget show --id <Id> --exact --source winget`.
6. **Not yet proven on real hardware.** The scripts were written against research on Windows 11
   Pro 26H2, not run end to end. Rehearse in the VM first and confirm:
   - Setup asks only for the disk, the account and the security questions.
   - `Install.ps1` completes, and after the restart `Confirm-Readiness.ps1` passes.
   - `.\Update.ps1 -Force` works with Administrator protection on (winget in the elevated profile).
   - `Enable-BitLocker.ps1` shows the key, takes the typed-back digits, and the PIN is asked at
     restart.
   - A setting you add by hand to VS Code's `settings.json` survives a second `Install.ps1`.
   - Cloning a repository that contains a symbolic link produces a real link.

## References

- Windows 11 release information: <https://learn.microsoft.com/en-us/windows/release-health/windows11-release-information>
- Answer files: <https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/windows-setup-automation-overview>
- Administrator protection: <https://learn.microsoft.com/en-us/windows/security/application-security/application-control/administrator-protection/>
- BitLocker countermeasures: <https://learn.microsoft.com/en-us/windows/security/operating-system-security/data-protection/bitlocker/countermeasures>
- Security baselines: <https://learn.microsoft.com/en-us/windows/security/operating-system-security/device-management/windows-security-configuration-framework/windows-security-baselines>
- WinGet: <https://learn.microsoft.com/en-us/windows/package-manager/winget/>
