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
| Windows Update | Left to Windows: stable updates install automatically, no release pin. Two policies: you have 2 days to restart after a monthly update before Windows does it, and Windows Update also updates other Microsoft products (.NET, Office, Visual Studio) |
| Accounts | One **local administrator account**, created by Windows Setup asking for a name and password. **Administrator protection** is on: you work without administrator rights and approve each elevation with Windows Hello. The built-in Administrator stays disabled. Your Microsoft account is signed in per app, not to Windows |
| Bloat, ads, AI | [Win11Debloat](https://github.com/Raphire/Win11Debloat), latest release: the maintainer's defaults with a short exception list ([system/debloat.ps1](system/debloat.ps1)) |
| Shell | Built-in settings only: extensions shown, Explorer opens to This PC, taskbar left with search and Task View hidden. Theme is left to Auto Dark Mode |
| Telemetry | Supported policies only. Pro's floor is "Required"; nothing is disabled by force |
| Security | Microsoft Defender with unwanted-app blocking, network protection and thirteen attack-surface rules ([system/defender.ps1](system/defender.ps1)), five settings from Microsoft's security baseline ([system/registry.psd1](system/registry.psd1)), and a `C:\` that only an administrator can create folders in |
| Encryption | BitLocker, XTS-AES-256, TPM + PIN. Other internal drives are encrypted the same way and unlock by themselves once `C:` is unlocked. Each recovery key is shown once for your password manager; it is never written to a file or uploaded |
| Apps | Microsoft Store first, then winget, then the vendor ([apps.psd1](apps.psd1)) |
| Browser | Microsoft Edge, signed in, with its enhanced security mode on and its own password saving off |

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
|   |-- registry.psd1          # every registry value the kit sets or relies on, with its reason
|   `-- machine, registry, defender, apps, debloat
|-- user/                      # AS YOU: your own account
|   |-- Install.ps1
|   |-- onedrive, apps, git, vscode/, terminal/, makemkv, tresorit
|   `-- Merge-JsonSettings.ps1 # helper (PowerShell 7): merge values into a JSON settings file
|-- security/
|   |-- Enable-BitLocker.ps1          # C: with TPM + PIN, XTS-AES-256, recovery key shown for your password manager
|   |-- Enable-BitLockerDataDrive.ps1 # another internal drive, unlocked automatically after C:
|   |-- bitlocker.ps1                 # helper shared by the two scripts above
|   `-- Confirm-Readiness.ps1         # read-only report on everything the kit sets and relies on
`-- test/New-TestVm.ps1        # Hyper-V VM for rehearsing the install
```

**Conventions.** Every script dot-sources `common.ps1`. A module is `Foo.ps1` or
`Foo/Install.ps1`; add one by dropping a script in and appending its name to the list in the
folder's `Install.ps1`. Modules are safe to re-run. The kit targets Windows PowerShell 5.1, which
every Windows install has; only the JSON merge uses PowerShell 7, which the kit installs first.

**Registry settings live in one table,** [system/registry.psd1](system/registry.psd1).
`Install.ps1` writes from it and `Confirm-Readiness.ps1` checks against it, so the two cannot
disagree. To add or change a setting, edit a line there; nothing else needs to change.

**Customize first:** the constants at the top of [common.ps1](common.ps1) (`$HostName`,
`$TimeZoneId`, `$GitName`, `$GitEmail`).

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
- **Nothing is logged to disk.** Each run ends by repeating its warnings, and the elevated
  window waits for Enter before it closes so you can read them. Win11Debloat keeps its own log
  and registry backups in the elevated profile.
- The kit runs from wherever you keep it (the USB at first, then your clone). **Your approval
  vouches for whatever is in that folder at that moment**, so keep the clone free of changes you
  did not make.

### Confirming Administrator protection

The account model depends on Administrator protection really being in effect, not just switched
on in the registry. The proof is that an elevated window runs as a **different account** than
yours: a hidden one that Windows manages. Three ways to see it:

- `.\security\Confirm-Readiness.ps1` has the row **Administrator protection in effect**. It
  passes only when the elevated window's account differs from yours, and shows both names.
- Every elevated kit window prints `Elevated as <account>, working for <you>`. If the setting
  is on but the two are the same account, the window warns that it is not in effect.
- By hand: the elevation prompt is a Windows Security prompt asking for Windows Hello or your
  password, not a Yes/No box, and `whoami` in an elevated terminal is not your account name.

It takes effect after the restart that follows the first `Install.ps1`. If it is still not in
effect after a restart, that Windows build is not applying the setting. The equivalent
protection is then a second, standard account for daily use, with this account kept for
elevation only.

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
   - Other internal drives, once `C:` has finished encrypting:
     `.\security\Enable-BitLockerDataDrive.ps1 -Drive D:` (see "Encrypting another drive")
   - Activate Windows with your Pro key
   - Sign in to the Store, Edge and Office with your Microsoft account. When Windows offers to
     use the account everywhere, choose **"Microsoft apps only"** so the Windows account stays local
   - Edge: turn off its ad and AI features, and turn on unwanted-app blocking (see below)
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
| `C:\` permissions | The two "Authenticated Users" entries removed from the drive's root, before anything else exists there |
| Compatibility links | Hidden links such as `C:\Documents and Settings` deleted at each account's first sign-in |

An answer file is processed once and never re-applied, so only what must be in place before the
first sign-in lives there. Everything else lives in `Install.ps1`, including the computer name,
time zone and 8.3 short names ([system/machine.ps1](system/machine.ps1)). Until that first run
the PC has a random name.

**`C:\` permissions.** By default any program can create a folder directly under `C:\` and
change what it creates there. A long line of privilege-escalation bugs rests on that: a program
without administrator rights plants `C:\something`, and a Windows service later reads it. With
the two entries gone only an administrator can. The cost: creating a folder directly under `C:\`
needs elevation, and a folder created that way belongs to the elevated account, so keep your
own folders in your profile or on another drive. `Confirm-Readiness.ps1` checks it, because a
yearly Windows release may put the entries back. To restore the default, elevated:
`icacls C:\ /grant "*S-1-5-11:(AD)" "*S-1-5-11:(OI)(CI)(IO)(M)"`.

**Compatibility links.** Windows keeps hidden links from where Windows XP stored things
(`C:\Documents and Settings`, `Application Data`, `My Documents`) to where they are now. The
answer file deletes them, for a cleaner listing and no file tool looping through them. Software
written for Windows XP with those paths hardcoded will not find its files; nothing newer is
affected. A yearly Windows release may restore some, which is harmless.

**8.3 short names.** The kit turns them off for new files and strips none. Files and folders
that Windows Setup and the first sign-in created keep their short name until they are deleted or
replaced. The run that turns the setting off counts them once and reports the number as a
warning; there is nothing to do about it. To see the count again, from an elevated terminal:
`fsutil 8dot3name scan /s C:\` (it changes nothing; delete the log file it names afterwards).

**Regenerating it.** The file's first comment is the generator URL that produced it. Open that
URL, change options, choose "View .xml file", and save the result over `media/autounattend.xml`.
It contains no personal details.

### Edge, by hand

Microsoft does not apply most Edge ad and AI policies to a profile signed in with a Microsoft
account. After signing in, turn these off once in `edge://settings` (they sync with your
account): the Copilot button and sidebar, shopping and rewards, new-tab-page content and feed,
"personalization & advertising". The kit still sets the Edge policies that do apply.

The kit also sets two security policies for Edge ([system/registry.psd1](system/registry.psd1)):
enhanced security mode (balanced), and Edge's own password saving off (passwords belong in your
password manager). Open `edge://policy` once: every policy Edge accepted is listed with status OK.

SmartScreen has no policy here, because Edge honors its SmartScreen policies only on a PC that
is domain-joined or enrolled in device management. SmartScreen itself is on by default. Its
blocking of unwanted apps is off by default: turn on **"Block potentially unwanted apps"** by
hand in `edge://settings/privacy`. Defender's own unwanted-app blocking, which the kit does turn
on, covers downloads from every browser either way.

### Encrypting another drive

For an internal drive other than `C:`, such as a media disk or a backup disk. The drive is
encrypted with XTS-AES-256 and unlocks by itself once `C:` has been unlocked with the PIN.

1. `C:` must be done first: `Enable-BitLocker.ps1`, restart, and wait until
   `manage-bde -status C:` shows it fully encrypted with protection on.
2. Connect the drive. If it is new, give it an NTFS volume and a drive letter in Disk Management.
3. Run, once per drive:
   ```powershell
   .\security\Enable-BitLockerDataDrive.ps1 -Drive D:
   ```
   It shows that drive's recovery key and waits until you have typed part of it back from your
   password manager. Save it with the title and key ID shown: the volume label tells the
   drives apart later, drive letters do not.
4. A large disk encrypts in the background and carries on after a restart. Keep it connected
   until `manage-bde -status D:` shows 100%.

Good to know:

- **Only the space in use is encrypted** by default, which is all a new or empty drive needs.
  For a drive that has ever held unencrypted files, add `-Full` (hours on a large hard disk),
  or run `manage-bde -WipeFreeSpace D:` afterwards.
- **A drive you keep disconnected** (the backup disk) needs nothing while it is unplugged. It
  unlocks by itself whenever it is connected.
- **Reinstalling Windows removes the automatic unlock**, because Windows keeps that key on
  `C:`. Each drive's recovery key must be in your password manager before a rebuild. After
  the rebuild, run the same command again for each drive: it asks for the recovery key,
  unlocks the drive and sets up automatic unlock again. Nothing is re-encrypted.
- **A SATA port with hot-plug turned on** makes Windows treat the disk as removable, and the
  script stops. Turn hot-plug off for that port in the BIOS.
- Suspending BitLocker on `C:` for a firmware update does not affect the other drives.
- To decrypt `C:`, run `Clear-BitLockerAutoUnlock` first (elevated); the other drives then lock
  at the next restart until you run the script for them again. To stop one drive unlocking
  automatically: `Disable-BitLockerAutoUnlock -MountPoint D:`.

---

## Keeping it current

```powershell
.\Update.ps1
```

| Updated by | What |
|---|---|
| `Update.ps1`, no elevation | Per-user winget apps |
| `Update.ps1`, one elevation, only when something is out of date | Machine-wide winget apps |
| Windows itself | Windows Update, Defender signatures, Store apps, and other Microsoft products (.NET, Office, Visual Studio) |
| The app itself | VS Code, Signal, Discord, Epic, Auto Dark Mode, Bing Wallpaper, NVIDIA App, Steam, Tresorit, Office |

Monthly updates are not held back: they install as soon as Microsoft releases them, as on any
Windows 11 PC, because attackers start studying a fix the day it is published. The kit changes
only the restart ([system/registry.psd1](system/registry.psd1)): you have **2 days**, and Windows
does not restart by itself during them. When they are up it restarts whether or not you are
signed in, after a 15-minute warning, and then waits at the BitLocker PIN prompt until you type
the PIN. Unsaved work in open apps is lost, and a long rip or backup is interrupted. The policy
counts in whole days, so the exact moment is the one Windows Update shows next to the pending
restart. The yearly feature update and driver updates are not covered by the deadline; they
restart the way Windows normally does, outside your active hours.

**When an update is reported to be faulty** before it has reached this PC, or before a long rip
or backup: Settings > Windows Update > "Pause updates" holds everything for a week at a time.
A few times a year a monthly update sends some PCs to the BitLocker recovery screen; that is
what the recovery key in your password manager is for, so keep it reachable from your phone.

Having an update policy means Windows holds some new monthly features until the yearly release
and shows a "managed" note on the update page.

**Vendor apps that arrive with drivers.** Windows Update delivers drivers, and a driver can name
a Microsoft Store app that Windows then installs with it (a monitor or audio control panel, for
example). No setting separates the two short of taking all drivers out of Windows Update. If an
app you do not want appears, uninstall it in Settings > Apps > Installed apps. If it returns,
block that one device with the policy "Prevent installation of devices that match any of these
device IDs" (`gpedit.msc` > Computer Configuration > Administrative Templates > System > Device
Installation > Device Installation Restrictions).

**Re-applying policies and the debloat tool:** re-run `Install.ps1`, for example after the yearly
Windows release. Each run does three things through Win11Debloat:

- It runs the then-latest release, so new maintainer defaults apply, and it removes the
  maintainer's default app list again. An app on that list that you installed since is removed
  unless it is in `$keepApps` in [system/debloat.ps1](system/debloat.ps1). Apps the maintainer
  leaves alone but you want gone, such as the new Outlook, go in `$alsoRemoveApps`.
- The tool makes a restore point, at most one a day, and turns System Restore on for `C:` if
  it was off.
- The tool saves a registry backup in the elevated profile, under
  `AppData\Local\Win11Debloat\Backups`. It can undo its own changes from one.

To see what a run would do without changing anything: `.\system\debloat.ps1 -DryRun`.

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

Vendor downloads ([user/tresorit.ps1](user/tresorit.ps1)) are fetched to the temp folder, run
with the vendor's own setup window, and deleted. Nothing is kept in the kit.

## Rehearsing in a VM

Rehearse before touching the real PC, and again after any change to the kit. The kit has not
yet been run end to end on real hardware, so the first rehearsal is also its first proof.

### Once, on the PC that hosts the VM

1. Windows 11 Pro or Enterprise, 16 GB of memory, about 40 GB free.
2. Enable Hyper-V from an elevated terminal, then restart:
   `Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All`
3. Download the Windows 11 ISO from <https://www.microsoft.com/software-download/windows11>
   ("Download Windows 11 Disk Image (ISO)"). The Media Creation Tool is not needed for this.
4. Administrator protection should be off on the host (Risks, item 2). The script warns if it is on.

The `Checkpoint-VM` and `Get-VMDvdDrive` commands below need an elevated terminal, or membership
of the local "Hyper-V Administrators" group.

### The run

```powershell
.\test\New-TestVm.ps1 -WinIso C:\iso\Win11.iso -Start      # add -DataDisk to rehearse a second drive
```

This creates the VM (generation 2, Secure Boot, virtual TPM), packs the answer file and the kit
into a small ISO as a second DVD, starts the VM, and presses the key at "Press any key to boot
from CD or DVD" for you. In the console window keep **View > Enhanced Session off**: the
BitLocker PIN screen and Windows Hello prompts only exist in the basic session.

1. **Windows Setup.** Pick the 100 GB disk, then type the account name, password and three
   security questions. *Expect:* Setup asks for nothing else.
2. **First sign-in.** Run `icacls C:\` and `Get-ChildItem C:\ -Force`. *Expect:* no
   "Authenticated Users" line, and no `Documents and Settings`.
   Then, on the host: `Checkpoint-VM -Name W11-kit-test -SnapshotName 1-setup`
3. **Install.** Run `E:\windows-setup-scripts\Install.ps1` (the kit DVD, usually `E:`).
   *Expect:* both halves complete, and each ends with a list of its warnings or with none.
   Restart.
4. **After the restart.** Set a Windows Hello PIN, open Settings > Windows Update and check for
   updates once, then run `.\security\Confirm-Readiness.ps1`. *Expect:*
   - Every row passes except the encryption rows, which wait for step 6.
   - "Administrator protection in effect" shows two different account names.
   - The memory integrity and LSA protection rows pass on a fresh install.
   - "Updates for other Microsoft products in effect" passes.
   - Settings > Windows Update > Advanced options: "Receive updates for other Microsoft
     products" and "Notify me when a restart is required" are on, and "Configured update
     policies" lists the restart deadline.
   - The Settings home page has no Microsoft 365 card, and the new Outlook is not installed.
   - `edge://policy` lists the kit's Edge policies with status OK.

   Then, on the host: `Checkpoint-VM -Name W11-kit-test -SnapshotName 2-installed`
5. **Second run.** Add a setting by hand to VS Code's `settings.json`, then run `Install.ps1`
   again, and `.\Update.ps1 -Force`. *Expect:* nothing changes, no new warnings, your setting
   survives, and the update's elevated half finds winget.
6. **BitLocker.** Copy the kit to the VM's disk
   (`robocopy E:\windows-setup-scripts $HOME\windows-setup-scripts /E`), eject both DVDs on the
   host (`Get-VMDvdDrive -VMName W11-kit-test | Set-VMDvdDrive -Path $null`), then run
   `.\security\Enable-BitLocker.ps1` from the copy. *Expect:* it shows the key, takes the
   typed-back digits, and the PIN is asked at the restart. Once encryption finishes, the
   encryption rows of the report pass.
   Then, on the host: `Checkpoint-VM -Name W11-kit-test -SnapshotName 3-encrypted`
7. **With `-DataDisk`.** *Expect:* `Enable-BitLockerDataDrive.ps1` shows one recovery key, the
   disk unlocks by itself after a restart, and after `Clear-BitLockerAutoUnlock` plus a restart
   the script unlocks the locked disk with the typed recovery key.
8. **Development.** Clone a repository that contains a symbolic link. *Expect:* a real link.
9. **If you can leave the VM running:** after a monthly update installs, the restart is forced
   about 2 days later and stops at the BitLocker PIN prompt.

### After editing a script

```powershell
.\test\New-TestVm.ps1 -RefreshKit      # rebuild the kit ISO and put it back in the VM's DVD drive
```

Inside the VM the DVD then holds the edited scripts; run them again from there. To retest from
a clean Windows instead of on top of the last run, go back to a checkpoint first:
`Restore-VMCheckpoint -VMName W11-kit-test -Name 1-setup -Confirm:$false`, then `-RefreshKit`.
A copy of the kit made inside the VM (step 6) is not refreshed.

When you are done: `.\test\New-TestVm.ps1 -Remove` deletes the VM, its disks and its checkpoints.

### What a VM cannot show

The NVIDIA driver and the graphics card's effect on BitLocker; the real TPM's behaviour;
fingerprint or face sign-in; anti-cheat, which mostly refuses to run in a VM; vendor apps that
arrive with drivers; HDR and VRR. An unactivated Windows also greys out the Personalization pages.

---
## Risks and gotchas

1. **BitLocker and firmware changes.** A BIOS update, a BIOS settings change or a GPU firmware
   update makes BitLocker ask for the recovery key at the next boot. Suspend it first:
   `manage-bde -protectors -disable C: -RebootCount 1`. The recovery key exists only where you
   saved it. The same goes for every other encrypted drive: after a Windows reinstall its
   recovery key is the only way back in.
2. **Administrator protection is new** (2026) and has changed since release. Check that it is
   in effect after every yearly Windows release (see "Confirming Administrator protection").
   - Microsoft says not to enable it on PCs that require Hyper-V. To run Hyper-V VMs, turn it
     off first and restart: Windows Security > Account protection, or set
     `TypeOfAdminApprovalMode` to `1` (see [system/registry.psd1](system/registry.psd1)).
     `Install.ps1` turns it back on. Microsoft gives no reason, so what fails is not known;
     `New-TestVm.ps1` warns when it finds the setting on.
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
   Pro 26H2, not run end to end. Rehearse in the VM first: "Rehearsing in a VM" lists what to
   confirm at each step.
## References

- Windows 11 release information: <https://learn.microsoft.com/en-us/windows/release-health/windows11-release-information>
- Answer files: <https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/windows-setup-automation-overview>
- Administrator protection: <https://learn.microsoft.com/en-us/windows/security/application-security/application-control/administrator-protection/>
- BitLocker countermeasures: <https://learn.microsoft.com/en-us/windows/security/operating-system-security/data-protection/bitlocker/countermeasures>
- Security baselines: <https://learn.microsoft.com/en-us/windows/security/operating-system-security/device-management/windows-security-configuration-framework/windows-security-baselines>
- WinGet: <https://learn.microsoft.com/en-us/windows/package-manager/winget/>
