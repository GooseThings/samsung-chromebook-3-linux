# Linux on a Samsung Chromebook 3 (XE500C13)

Debian 13 (Trixie) + Cinnamon on a Samsung Chromebook 3 (XE500C13, Intel
Celeron N3060 "Braswell", coreboot board `celes`) after flashing
MrChromebox Full ROM (UEFI/edk2) firmware.

- **Unit 1** — retired. `memtest86+` found severe soldered-RAM failure; not
  economical to repair on a $9 board. See [Unit 1](#unit-1--retired-bad-ram).
- **Unit 2** — the live machine (hostname `chromux`, user `levi`). Passed
  `memtest86+`, firmware flashed, power-tuned. See
  [Unit 2](#unit-2--live-machine).

The full step-by-step diagnostic narrative that used to live here is in the
git history (through commit `62b59a9`) if the reasoning behind any fix is
needed.

## Hardware

- Samsung Chromebook 3 — XE500C13
- SoC: Intel Celeron N3060 (Braswell), 2 cores, `x86_64`
- Firmware: MrChromebox Full ROM (UEFI/edk2), coreboot board `celes`
  (`Hardware name: GOOGLE Celes/Celes, BIOS MrChromebox-2606.1 07/14/2026`)
- GPU: Intel Cherryview (PCI `22b1`), driver `i915`
- Touchpad: Atmel maXTouch (`atmel_mxt_ts`, `ATML0000:00`)
- RAM: 3.8GB, **soldered** (no SO-DIMM) — failing on unit 1, healthy on unit 2

## Firmware & install (applies to any unit)

| Step | What to do |
|------|-----------|
| **Disable write-protect** | Physical only: disassemble, flip the motherboard, remove the one screw on the underside with a printed **arrow** pointing at it (small washer under it). Disconnect the battery first. Verify: `crossystem wpsw_cur` → `0`, `flashrom -p host --wp-status` → disabled. |
| **Flash firmware** | `firmware-util.sh` → "Install/Update UEFI (Full ROM) Firmware". Back up stock first off-device: `flashrom -p host -r stock-backup.bin`. If flashing over SSH, run the flash detached (`setsid`) so a dropped connection can't brick it mid-write. |
| **Installer** | Use the **netinst** installer, not live-Cinnamon/Calamares (Calamares failed at "installing the system", bare error 1). |
| **GRUB / EFI** | If netinst asks *"Force GRUB installation to the EFI removable media path?"*, **answer yes** (`\EFI\BOOT\BOOTX64.EFI`) — MrChromebox/coreboot NVRAM boot entries are flaky. (Unit 2 happened to register a normal NVRAM entry fine, so it's not guaranteed to fail — just be ready.) |
| **Sudo access** | Debian only auto-adds the user to `sudo` if the root password is left blank at install. If you set a root password, run `usermod -aG sudo <user>` as root afterward. |
| **SSH** | Debian's `sshd` defaults to `PermitRootLogin prohibit-password` — use a sudo-capable non-root user over SSH; don't loosen `sshd_config`. |

Enabling SSH from **ChromeOS dev mode** (before flashing) hits
`passwd: Authentication token lock busy` because rootfs verification keeps
`/etc` read-only. Fix:

```sh
sudo /usr/share/vboot/bin/make_dev_ssd.sh --remove_rootfs_verification
sudo reboot
# after reboot:
mount -o remount,rw /
passwd root
/usr/libexec/debugd/helpers/dev_features_ssh   # check with: initctl list | grep ssh
```

Write-protect screw references:
[teardown w/ photos](https://maxwyb.github.io/linux/2016/11/05/chromebook-write-protection.html),
[chrultrabook thread](https://forum.chrultrabook.com/t/samsung-chromebook-3-celes-write-protect-screw-access/2694).

## Unit 2 — live machine

Problems and fixes, most involved first.

### `i915` display corruption under GPU load — fix in soak-test

Flicker → black screen with garbage lines, no cursor, under GPU/video load.
Machine stays reachable (not a hard-lock, kernel never tainted). Errors seen:
`pipe A FIFO underrun`, `Atomic update failure on pipe A`, `Unexpected
PHY_STATUS` (a low-level DPIO PHY mismatch).

**Fix (two parts, currently soaking):**
1. `i915.enable_psr=0` on the kernel cmdline — see
   [`scripts/set-i915-kernel-params.sh`](scripts/set-i915-kernel-params.sh).
   Covered the first trigger but not all of them.
2. Pin the GPU RPS frequency to a fixed 320MHz — see
   [`scripts/install-i915-gpu-freq-pin.sh`](scripts/install-i915-gpu-freq-pin.sh)
   (installs [`scripts/pin-i915-gpu-freq.sh`](scripts/pin-i915-gpu-freq.sh) as
   `pin-i915-gpu-freq.service`). Borrowed from the sibling repo's GPU-devfreq
   fix. **Zero new `i915` errors since applying it**, across the exact
   conditions that used to trigger the bug — promising but not yet proven.

Untried if the pin fails: a newer kernel than Debian's stock 6.12.107 (the
PHY-readiness code changed upstream as recently as Feb 2025).

### Power-tuning settings that don't survive reboot

`scripts/tune-power-settings.sh` applies TLP, `schedutil`, zswap (`zstd`/30%),
`vm.swappiness=60`, Bluetooth off. Two settings silently revert on reboot and
are fixed by a boot-time oneshot the script installs
(`power-tuning-boot-fixup.service`):
- `zswap.compressor=zstd` falls back to `lzo` (applied before the `zstd`
  module loads) → `zstd` in `/etc/modules-load.d/` + re-echo to sysfs at boot.
- `rfkill block bluetooth` doesn't persist (`systemd-rfkill` is masked) →
  re-applied at boot.

Script: [`scripts/tune-power-settings.sh`](scripts/tune-power-settings.sh).

### Sluggish under load (2 cores, 3.8GB)

Genuine hardware ceiling, not a misconfig (29 Firefox tabs + Discord = real
CPU/RAM demand). Reduce desktop overhead:

```sh
gsettings set org.cinnamon desktop-effects false
gsettings set org.cinnamon desktop-effects-on-menus false
gsettings set org.cinnamon desktop-effects-on-dialogs false
gsettings set org.cinnamon.muffin unredirect-fullscreen-windows true
```

Also: `vm.swappiness=60` (traded off some battery-life tuning for
responsiveness), and disabled `gnome-software`'s login autostart (it was the
largest resident memory user in ~90% of samples) by shadowing
`/etc/xdg/autostart/org.gnome.Software.desktop` with a `Hidden=true` copy in
`~/.config/autostart/` — freed ~160MB.

### Full system hang under heavy load — not a bug

Under 29 tabs + Discord the machine went fully unreachable (needed a
power-cycle). The resource-monitor log confirmed real memory exhaustion /
swap-thrashing (~212MB free, ~274MB swap, load avg peaking 15.9 on 2 cores) —
a resource ceiling, not a driver fault. Mitigation: don't run that much at
once. A continuous logger is installed to catch future events:
[`scripts/install-resource-monitor.sh`](scripts/install-resource-monitor.sh)
→ [`scripts/system-resource-monitor.sh`](scripts/system-resource-monitor.sh)
(CSV in `/var/log/resource-monitor/`, every 5s).

### Screensaver crash-loop — resolved (was a misdiagnosis)

Earlier thought to be a failing PAM `account` phase
(`pam_unix(cinnamon-screensaver:account): setuid failed`). Retested with an
isolated `pam_acct_mgmt` harness and a full instrumented lock/unlock cycle:
that log line is **benign** (pam_unix can't read `/etc/shadow` unprivileged,
logs it, then returns success anyway), and unlock works cleanly with no crash.
The crash-loop was transient/environmental (memory pressure), not a PAM defect.

**Done:** reverted `/etc/pam.d/cinnamon-screensaver` to the distro default
(removed the earlier `@include common-account` addition) to drop the
misleading log line. **Auto-lock is off by preference**, not as a workaround.

### Top-row keys — work as F1–F10

On the current firmware (MrChromebox-2606.1) the top-row keys emit ordinary
**F1–F10** (verified with `xev`). Section-12-era firmware emitted nothing; a
newer firmware added the Braswell EC keyboard support. **Kept as F-keys by
preference.** To instead get the printed Chromebook actions, install a udev
hwdb override matching `evdev:atkbd:dmi:*svnGOOGLE:pnCeles:*` mapping the AT
scancodes to `KEY_BACK`/`KEY_FORWARD`/`KEY_REFRESH`/`KEY_BRIGHTNESSDOWN`/
`KEY_BRIGHTNESSUP`/`KEY_MUTE`/`KEY_VOLUMEDOWN`/`KEY_VOLUMEUP`, plus Cinnamon
shortcuts for the fullscreen/overview keys (`intel_backlight` is present, so
brightness works). Not applied.

### Touchpad hard-lock (from unit 1) — did not reproduce

Unit 1's Atmel touchpad could hard-lock the whole machine; on unit 2 (healthy
RAM) it hasn't reproduced under deliberate testing. If it ever does, unbind +
blacklist the driver:
[`scripts/disable-atmel-touchpad.sh`](scripts/disable-atmel-touchpad.sh). Two
community reports of the same symptom on this exact board:
[MrChromebox/firmware#125](https://github.com/MrChromebox/firmware/issues/125),
[GalliumOS#415](https://github.com/GalliumOS/galliumos-distro/issues/415).

### Ham radio / app install gotchas

- **MSHV** — no Linux binary upstream, but builds from source: `apt install
  qtbase5-dev qt5-qmake libasound2-dev libfftw3-dev libpulse-dev
  libqt5websockets5-dev libqt5serialport5-dev`, then
  `qmake MSHV_x86_64.pro && make` (~10 min on this CPU).
- **Pat** (Winlink) — install the upstream GitHub `.deb` over Debian's older
  package: `apt install ./pat_*.deb`. (`/api/config` `PUT` is a full replace,
  not a merge — don't test it with partial JSON or it wipes the config.)
- **HAMRS** — AppImage needs FUSE2: `apt install libfuse2t64` (Debian 13 ships
  only `fuse3`).
- **flrig**, **Discord**, **GridTracker 2** — distro repo / vendor `.deb`,
  no issues.

### Credentials

Set to real values during the netinst install (no vendor default), so
[`scripts/harden-default-credentials.sh`](scripts/harden-default-credentials.sh)
isn't needed here — it's for install methods that leave a default password.

## Open items (unit 2)

- **`i915` fix** — soak-test the 320MHz RPS pin (only `i915.enable_psr=0` left
  on the cmdline). Check `journalctl -b -k | grep -i i915` (not `dmesg` —
  restricted for `levi`) before assuming any "black screen" is this bug; the
  OOM hang and the old screensaver loop looked identical.
- **Longer multi-pass `memtest86+`** — only one quick clean pass done.
- **`soundmodem.service`** fails to start — unconfigured leftover from the
  `pat`/`ax25-tools` install, harmless.

## Unit 1 — retired (bad RAM)

`memtest86+` found **severe soldered-RAM failure** (3000 then 8314 errors,
freezing before completing a pass). RAM is soldered → not repairable on a $9
unit, so the unit is retired and anything installed on it should be treated as
possibly corrupted.

The symptoms chased before that verdict — a touchpad hard-lock, an `i915`
page-flip NULL-pointer oops, SLUB/heap corruption across unrelated processes,
a `polkitd` segfault — are all consistent with bad RAM corrupting anything,
and were never confirmed as independent bugs. **Lesson applied to unit 2: run
`memtest86+` first**, before chasing any driver-level symptom
([`scripts/install-memtest86-grub-entry.sh`](scripts/install-memtest86-grub-entry.sh)).

## Diagnostics cheat sheet

```sh
# firmware/board identity from the running kernel
dmesg | grep -i "Hardware name"          # GOOGLE Celes/Celes, BIOS MrChromebox-...

# confirm genuinely 64-bit before trusting a memtest86+ result
lscpu | grep -E "Architecture|Model name|CPU op-mode"

# a specific IRQ's fire count (watch during touchpad testing)
grep -i atml /proc/interrupts

# kernel taint state (128 = TAINT_DIE, a prior oops; 0 = clean)
cat /proc/sys/kernel/tainted

# is a hung process stuck in the kernel (D state)?
ps aux | grep ' D '

# list boots / read a specific boot's log
journalctl --list-boots
journalctl -b -1 --no-pager

# i915 GPU frequency scaling state
cat /sys/class/drm/card0/gt_{min,max,cur}_freq_mhz

# zswap current config
cat /sys/module/zswap/parameters/{enabled,max_pool_percent,compressor}

# recent i915 display errors (levi reads the journal, not raw dmesg)
journalctl -b -k | grep -iE 'i915.*ERROR|underrun|PHY_STATUS'

# which processes hold GPU fds (is an app really off the GPU?)
sudo fuser -v /dev/dri/*

# i915 PSR state -- suspect #1 for flicker under load (-1 = default/on, 0 = off)
cat /sys/kernel/debug/dri/0000:00:02.0/i915_params/enable_psr

# does the EC expose a sub-device (e.g. keyboard-matrix) to the kernel?
find /sys/bus/platform/devices/cros-ec-dev.*.auto/ -maxdepth 1

# what a key actually sends (needs root / input group)
sudo evtest /dev/input/event0
```

## Repo contents

- [`scripts/disable-atmel-touchpad.sh`](scripts/disable-atmel-touchpad.sh) —
  unbind + blacklist the Atmel touchpad driver (for the unit 1 hard-lock).
- [`scripts/install-memtest86-grub-entry.sh`](scripts/install-memtest86-grub-entry.sh)
  — install `memtest86+` and keep the GRUB menu visible long enough to pick it.
- [`scripts/harden-default-credentials.sh`](scripts/harden-default-credentials.sh)
  — interactively change a weak default password (prompts twice, refuses
  empty). Only needed for install methods that leave a default.
- [`scripts/tune-power-settings.sh`](scripts/tune-power-settings.sh) —
  TLP/`schedutil`, zswap+swappiness (60), Bluetooth off; installs a boot-time
  fixup for the two settings that don't persist.
- [`scripts/set-i915-kernel-params.sh`](scripts/set-i915-kernel-params.sh) —
  set `i915.enable_psr=0`; removes the `enable_dc`/`disable_power_well`
  experiments that didn't help.
- [`scripts/install-i915-gpu-freq-pin.sh`](scripts/install-i915-gpu-freq-pin.sh)
  → [`scripts/pin-i915-gpu-freq.sh`](scripts/pin-i915-gpu-freq.sh) — boot-time
  service pinning GPU RPS to 320MHz (the current `i915` experiment).
- [`scripts/install-resource-monitor.sh`](scripts/install-resource-monitor.sh)
  → [`scripts/system-resource-monitor.sh`](scripts/system-resource-monitor.sh)
  — continuous load/memory/swap/thermal CSV logger (`/var/log/resource-monitor/`).
