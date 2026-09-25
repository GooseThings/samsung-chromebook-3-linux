# Linux on a Samsung Chromebook 3 (XE500C13)

Getting Debian 13 (Trixie) + Cinnamon running on a Samsung Chromebook 3
(XE500C13, Intel Celeron N3060 "Braswell") after flashing MrChromebox UEFI
firmware. This chased a genuinely wild string of software-looking symptoms
— a touchpad that could hard-lock the entire machine, an `i915` GPU driver
crash, a kernel heap-corruption bug — before `memtest86+` revealed the
actual cause: **the RAM itself is failing.** Total cost of the unit: $9.
Documenting the diagnostic chain anyway, since most of the individual bugs
chased along the way are real, independently-useful findings (and might be
the actual cause if the same symptom shows up on a healthy board).

A second unit is inbound — see `CLAUDE.md` for how this repo should evolve
once it arrives.

## TL;DR

- MrChromebox **Full ROM (UEFI/edk2)** firmware flash worked as planned —
  confirmed via `BIOS MrChromebox-2606.1` in kernel log output and an
  Esc-only UEFI Boot Manager (no ChromeOS dev-mode `Ctrl+L` step ever
  needed), matching this repo's original prep notes.
- The **live-Cinnamon/Calamares installer failed** partway through
  ("installing the system", bare error code 1), never fully isolated.
  Switched to the plain **netinst** installer instead, which succeeded
  (after one transient retry — see section 3).
- The touchpad (Atmel maXTouch, `atmel_mxt_ts`) could **hard-lock the
  entire machine** under sustained interaction — no panic, no log line,
  the box just goes silent and unreachable. Matches an open, unresolved
  community bug report on this *exact* board+firmware combination. Root
  cause never fully confirmed on its own, because...
- ...`memtest86+` ultimately found **severe RAM failure**: 3000 errors on
  one pass, 8314 on the next, freezing before either pass completed. That
  retroactively makes every other "driver bug" below suspect as a possible
  RAM-corruption symptom rather than an independent bug. RAM is soldered
  on this board — not economical to repair on a $9 device.

## Hardware

- Samsung Chromebook 3 — XE500C13
- SoC: Intel Celeron N3060 (Braswell) — confirmed via `lscpu`
  (`Model name: Intel(R) Celeron(R) CPU N3060 @ 1.60GHz`, 2 cores) and
  `uname -a` (`x86_64`)
- Firmware: MrChromebox Full ROM (UEFI/edk2), coreboot board name `celes`
  — confirmed via kernel log: `Hardware name: GOOGLE Celes/Celes, BIOS
  MrChromebox-2606.1 07/14/2026`
- GPU: Intel Cherryview (PCI device ID `22b1`), driven by `i915`
- Touchpad: Atmel maXTouch (`atmel_mxt_ts`, i2c device `ATML0000:00`,
  Family 164 / Variant 17, firmware `V2.0.AA`)
- RAM: 3.8GB, **soldered to the board** (no SO-DIMM slot) — and, per
  `memtest86+`, failing badly

## The saga

### 1. Firmware + install media — mostly per plan

Developer Mode + MrChromebox Full ROM flash (per this repo's original
plan) went as expected — no beeps, no ChromeOS dev-mode screen, straight
to a UEFI Boot Manager on `Esc`. Confirmed the firmware actually took via
the kernel's own `Hardware name: GOOGLE Celes/Celes, BIOS
MrChromebox-2606.1` string once Linux was up — this is a completely
standard 64-bit UEFI PC at this point, no ARM-style image-builder or
device-tree concerns the way the sibling repo needed.

Standard Debian 13 (Trixie) **live-Cinnamon amd64** ISO
(`debian-live-13.6.0-amd64-cinnamon.iso`, checksum-verified against the
official `SHA256SUMS`) was `dd`'d to an SD card and booted fine from the
firmware's Boot Manager.

### 2. Live/Calamares installer fails at "installing the system" (error code 1)

The Calamares installer (bundled in the live-Cinnamon image) crashed
partway through with a bare "error code 1" — no further detail surfaced
in the dialog, and it wasn't isolated to a specific job/log line before
moving on to a different installer entirely. Leading suspect in hindsight:
MrChromebox's UEFI (edk2) firmware has known-flaky NVRAM boot-entry
persistence (see section 4's linked GitHub issue for the same firmware
exhibiting flaky I2C too — general firmware-level flakiness on this board
isn't a one-off), and GRUB's install step (which Calamares drives non-
interactively) can fail non-obviously if the bootloader-registration part
of that job doesn't behave the way Calamares expects.

Rather than dig further into Calamares specifically, switched to the plain
**netinst** installer (`debian-13.6.0-amd64-netinst.iso`, also checksum-
verified), which uses the traditional `debian-installer` — more verbose
failure reporting, manual partitioning control, and it succeeded.

**Recommendation for next time**: at netinst's GRUB-install step, if/when
it asks *"Force GRUB installation to the EFI removable media path?"* —
**answer yes**. MrChromebox/coreboot UEFI NVRAM boot-entry support is a
known-flaky area; writing GRUB to the removable path
(`\EFI\BOOT\BOOTX64.EFI`) sidesteps depending on it entirely.

### 3. netinst `pkgsel` failure (error code 127) — transient

Hit once: `pkgsel` (the tasksel/package-install step) failed with
**127 = "command not found"**, which usually means a truncated `.deb`
download left a maintainer script unable to find a binary it needed.
Chose "Continue", re-ran "Select and install software" from the
installer's main menu, and it succeeded on retry. Never recurred, so no
further isolation was done.

### 4. Touchpad hard-locks the entire machine (Atmel maXTouch / `atmel_mxt_ts`)

First reported symptom: touching the touchpad would lock the screen; a
longer interaction (~60s of tapping/dragging) escalated to a full hard
freeze — machine completely unreachable (`ping`: "Destination Host
Unreachable"), and the previous boot's `journalctl -b -1` log simply
**stopped dead** at the moment of the touch, no panic, no OOM, no
watchdog warning. That total-silence pattern (nothing even gets a chance
to log) is the signature of a hard lockup, not a clean crash.

Kernel log showed the controller running without its calibration data:

```
atmel_mxt_ts i2c-ATML0000:00: firmware: failed to load maxtouch.cfg (-2)
atmel_mxt_ts i2c-ATML0000:00: Direct firmware load for maxtouch.cfg failed with error -2
```

(ChromeOS ships a board-specific `maxtouch.cfg`; Debian doesn't.) The IRQ
line for this device is ACPI GPIO-based:

```
183:  ...  chv-gpio  18  ATML0000:00
```

— consistent with an interrupt storm being the actual crash mechanism
(an uncalibrated touch controller misbehaving badly enough to wedge the
GPIO IRQ line hard enough that nothing, not even `journald`, gets a
chance to flush a log line).

This isn't unique to this unit — it matches two open, unresolved
community reports on this *exact* hardware:

- [MrChromebox/firmware#125](https://github.com/MrChromebox/firmware/issues/125)
  — intermittent I2C failures on CELES affecting *both* the trackpad and
  the SD card reader, specifically noting *"this behavior only happens
  when running the Full Firmware for CELES (UEFI)"* — i.e. possibly a
  firmware-level I2C controller issue, not purely a Linux driver bug.
- [GalliumOS/galliumos-distro#415](https://github.com/GalliumOS/galliumos-distro/issues/415)
  — the same trackpad-freeze symptom on two separate Samsung Chromebook 3
  units, never permanently resolved.

**Mitigation used** (not a confirmed fix): unbind the driver live and
blacklist it so it doesn't load at all —
[`scripts/disable-atmel-touchpad.sh`](scripts/disable-atmel-touchpad.sh).
Re-enabling it afterward and testing progressively (single tap → short
drag → ~15s of normal use, checking `/proc/interrupts`'s IRQ-183 count
and `dmesg` after each step) survived without incident, which doesn't
rule out the bug — it only shows it isn't guaranteed on every touch.

**Caveat**: given section 8's RAM finding, it's now unclear whether this
was a real, independent touchpad/firmware bug (as the two linked issues
suggest for other units) or an early symptom of this specific unit's
failing memory. Both are plausible; this was never re-tested on
confirmed-good RAM.

### 5. `i915` (Cherryview) GPU driver crash during a page-flip

A separate, later freeze left an actual kernel oops in the log (unlike
section 4's silent lockups) — this one killed Xorg outright rather than
freezing the whole box:

```
BUG: unable to handle page fault for address: 0000000000000000
...
RIP: 0010:drm_mode_object_get+0x24/0x70 [drm]
Call Trace:
 drm_property_blob_get+0x12/0x20 [drm]
 __drm_atomic_helper_crtc_duplicate_state+0x56/0xd0 [drm_kms_helper]
 intel_crtc_duplicate_state+0x40/0x120 [i915]
 drm_atomic_get_crtc_state+0x7b/0x130 [drm]
 page_flip_common+0x2f/0xe0 [drm_kms_helper]
 drm_atomic_helper_page_flip+0x55/0xd0 [drm_kms_helper]
 drm_mode_page_flip_ioctl+0x5be/0x6e0 [drm]
```

A NULL-pointer read inside the DRM atomic-modeset code, triggered by
Xorg's own page-flip ioctl. Restarting `lightdm.service` did **not**
recover the display — the fresh Xorg process just hung in an
uninterruptible kernel wait (`ps` showed state `D`) trying to touch the
same corrupted CRTC state, confirming the damage was at the kernel/driver
level, not just a dead userspace process. Only a full reboot cleared it
(`cat /proc/sys/kernel/tainted` read `128` = `TAINT_DIE` beforehand, `0`
after rebooting).

This is the most likely explanation for the original "screen goes crazy
when I open Firefox" report — Cherryview's display driver doing frequent
page-flips under compositor/video load, hitting this same crash path.

### 6. Kernel heap corruption + an unrelated daemon segfault

Two further incidents, on two different boots, that turned out to be the
real tell:

- A page-fault oops in the SLUB allocator (`kmem_cache_alloc_node_noprof`)
  hit **twice in a row, milliseconds apart, in two completely unrelated
  processes** — Firefox's "Privileged Content" process (via a Unix-socket
  send) and then `systemd-journald` (via `fork()`), both crashing at the
  *same instruction* with a bad read. The same allocator crashing for
  unrelated callers back-to-back is the classic signature of slab/heap
  corruption — something already overwrote the allocator's own
  bookkeeping.
- `polkitd` (a completely unrelated system daemon) segfaulted inside
  `libc.so.6` itself for no apparent reason:
  `polkitd[658]: segfault at 0 ip 00007f9d6bfdf545 ... error 6 in libc.so.6`.

Crashes and corruption scattered across totally unrelated processes and
subsystems — not something reproducibly tied to one driver or one code
path — is a much stronger signal of a **hardware** memory fault than of
independent software bugs, which is what prompted section 8.

### 7. GPU max-pin and zswap tuning — applied, then reverted

Two performance changes were made along the way and are worth recording
as **ruled out**, not recommended:

- Pinned the `i915` GPU to its max clock (`gt_min_freq_mhz` =
  `gt_max_freq_mhz` = 600) via a boot-time systemd oneshot service.
  Reverted after two crashes happened while it was active, on the
  (unproven) theory that sustained max GPU clock was adding thermal/power
  stress. In hindsight, given section 8, this was probably never the
  actual cause — but it wasn't confirmed safe either, so it stays
  reverted.
- Enabled `zswap` with `zstd` compression and a 30% pool (up from the
  distro default of `lzo`/20%) to help with the 3.8GB RAM constraint.
  Reverted back to defaults for the same reason as above — plausible
  contributing factor to memory pressure/corruption, never confirmed
  either way.

**Recommendation for the next unit**: don't bother re-applying either of
these until the RAM itself is confirmed good with a clean `memtest86+`
run — there's no point tuning performance on hardware that might still be
silently corrupting data.

### 8. The actual root cause: `memtest86+` finds severe RAM failure

Installed `memtest86+` (adds itself to the GRUB menu automatically via
`update-grub`) and booted it directly, ruling out every software layer at
once. Two separate runs:

- Run 1: **3000 errors**, froze before completing a full pass.
- Run 2: **8314 errors**, froze before completing a full pass.

This is severe, worsening-between-runs memory corruption — not a
marginal/borderline result, and not something a `memmap=` kernel
exclusion of one bad address range would meaningfully help with (the
volume of errors suggests much of the chip is affected, not one narrow
region). Confirmed this was a genuine 64-bit test on real hardware first
(`lscpu`/`uname -a` both show `x86_64`, and `update-grub` picked up both
the 64-bit and 32-bit `memtest86+` EFI images correctly).

The RAM on this board is **soldered**, not a SO-DIMM — so this isn't
user-repairable without BGA rework equipment, which isn't worth it for a
$9 unit. This single finding retroactively explains sections 4-6 far
better than any of the individual driver theories chased along the way:
bad RAM can corrupt *anything*, which is exactly the "scattered across
unrelated subsystems" pattern that kept showing up.

## Status

This unit is retired — RAM failure confirmed by `memtest86+`, not
economical to repair. A second (hopefully healthy) unit is inbound; see
`CLAUDE.md` for how to proceed once it arrives. **Anything installed on
this unit should be treated as possibly corrupted** — bad RAM causes
silent data corruption, not just crashes (a `systemd-journald` journal
file was already flagged mid-session as "corrupted or uncleanly shut
down").

Still outstanding, to redo on the next (hopefully healthy) unit:
- Harden the default account password — see
  [`scripts/harden-default-credentials.sh`](scripts/harden-default-credentials.sh).
  Never got to this before the RAM finding took priority.
- Re-verify whether the touchpad freeze (section 4) and the `i915`
  page-flip crash (section 5) are real, independent bugs or were RAM-
  corruption symptoms all along — only possible to know on confirmed-good
  memory.

## Unit 2 (2026-09-25)

A second CELES unit arrived and, unlike unit 1, made it through the full
plan cleanly: firmware flash, Debian install, and a clean `memtest86+`
pass, with neither of unit 1's headline bugs (the touchpad hard-lock, the
`i915` page-flip crash) reproducing so far. Documented as its own section
per this repo's `CLAUDE.md`, rather than editing unit 1's writeup above.

### 1. Enabling SSH from ChromeOS dev mode hit a real rootfs-verification wall

`passwd root` (part of getting `dev_features_ssh`-based SSH access working)
failed with **"Authentication token lock busy"**. This wasn't a stale lock
file — it was ChromeOS's rootfs verification still being active, making
`/etc` genuinely read-only, so `passwd` couldn't create its lock file at
all. Fixed with:

```sh
sudo /usr/share/vboot/bin/make_dev_ssd.sh --remove_rootfs_verification
sudo reboot
# after reboot:
mount -o remount,rw /
passwd root
/usr/libexec/debugd/helpers/dev_features_ssh
```

`openssh-server` was already running as an upstart job after that — ChromeOS
uses `initctl`/upstart, not systemd or SysV `service`, so `initctl list |
grep ssh` is the right way to check job status here, not `service sshd
status`.

### 2. Same board, confirmed the same way as unit 1

HWID `CELES D25-D6G-T6B-I6U`, board name `celes` — same identification
approach as unit 1's section 1 (`crossystem hwid`, `dmesg | grep
"Hardware name"` once Linux was up).

### 3. Disabling write-protect required real disassembly

`crossystem wpsw_cur` read `1` (closed) out of the box — a Full ROM flash
needs it `0`. Unlike the software-side rootfs issue above, this is a
physical hardware switch: a screw on the motherboard, not a jumper or
firmware setting. Procedure (battery physically disconnected first — a
guide's author specifically warned that powering off the OS is *not* the
same as removing power from internal cables):

1. Remove the back panel.
2. Remove the screws holding the motherboard down; disconnect the two
   ribbon cables blocking it from flipping (one via a rotating plastic
   locking tab, one via a metal handle along the connector's edge).
3. Flip the motherboard over.
4. Find **the only screw on the backside with an arrow printed pointing at
   it** (with a small metal washer under it) — that's the write-protect
   screw. Remove it.
5. Reassemble.

Confirmed via `crossystem wpsw_cur` (`1` → `0`) and `flashrom -p host
--wp-status` (`write protect is disabled`) after reassembly and reboot.

Sources: [maxwyb.github.io teardown w/ photos](https://maxwyb.github.io/linux/2016/11/05/chromebook-write-protection.html),
[chrultrabook forum thread](https://forum.chrultrabook.com/t/samsung-chromebook-3-celes-write-protect-screw-access/2694).

### 4. MrChromebox Full ROM flash — succeeded on the first attempt

Ran `firmware-util.sh` → "Install/Update UEFI (Full ROM) Firmware". Two
things worth doing differently from just running the script interactively
at the keyboard, given this was driven over SSH:

- **Backed up the stock firmware off-device first**, independent of the
  script's own backup option (which requires a FAT32 USB stick to be
  physically connected and interactively selected — extra friction when
  there isn't one to hand):
  ```sh
  flashrom -p host -r /tmp/stock-firmware-backup.bin
  ```
  then `scp`'d it off the device before flashing, so a known-good stock
  image survives even if the flash bricks the device or the disk gets
  wiped.
- **Ran the flash detached from the SSH session** (`setsid bash -c
  '... < answers.txt > flash.log 2>&1 &'`) so an ~90-second SPI flash
  write wouldn't be at risk of dying from a dropped SSH connection —
  the flash write itself doesn't depend on the network, but the parent
  shell process does, and losing it mid-write would be exactly the kind
  of interruption that bricks a device.

Result: `Full ROM firmware successfully installed/updated`, no retry
needed. Confirmed post-reboot via `dmesg | grep DMI`:
`GOOGLE Celes/Celes, BIOS MrChromebox-2606.1 07/14/2026` — matches unit 1's
firmware string exactly.

### 5. Debian netinst install — no Calamares detour needed this time

Went straight to the **netinst** installer per unit 1's own recommendation
(section 2), skipping the live-Cinnamon/Calamares path entirely. Installed
cleanly with no retries. At the GRUB-install step, this run actually
registered a proper NVRAM boot entry (`efibootmgr` showed `Boot0004*
debian`, active as `BootCurrent`) without needing the "force EFI removable
media path" fallback unit 1's writeup warned about — so that NVRAM
flakiness isn't universal on this firmware, just something to watch for,
not something to assume will happen.

### 6. Two sudo/SSH gotchas specific to Debian's installer defaults

- Debian's installer only auto-adds the primary user to the `sudo` group
  if the **root password field is left blank** during install. Since a
  root password was set (alongside the normal user account), the user
  account had no sudo access after first boot — `usermod -aG sudo
  <user>` (run as root) fixes it.
- Debian's `sshd` ships with `PermitRootLogin prohibit-password` by
  default — root password login works fine at the **local console**
  (`su -`) but is correctly rejected over SSH even with the right
  password. This is expected hardening, not a bug: the fix is to get a
  sudo-capable non-root user working over SSH (previous bullet), not to
  loosen `sshd_config`.

### 7. `memtest86+` run early this time — clean pass

Per unit 1's explicit lesson (README section 8, `CLAUDE.md` priority #2),
ran `scripts/install-memtest86-grub-entry.sh` and booted straight into
`memtest86+` **before** installing the desktop environment or re-testing
any driver-level symptoms. Result: **0 errors on a full pass** — a clean
contrast to unit 1's 3000-then-8314-error result that froze before
completing even one pass. This unit's RAM looks genuinely healthy.

### 8. Cinnamon — already installed via netinst's own software selection

Unlike unit 1 (installed via live-Cinnamon media), this unit went through
netinst's tasksel software-selection screen, and `task-cinnamon-desktop`
ended up installed directly from there (`lightdm` + `slick-greeter`,
`graphical.target` as default) — no separate `apt install` step was
actually needed by the time it was checked.

### 9. Touchpad hard-lock and `i915` crash (unit 1 sections 4-5) — did not reproduce

With RAM now confirmed healthy, both of unit 1's headline symptoms were
re-tested directly: progressive touchpad interaction (tap → drag → ~30-60s
of normal use) and GPU load (video playback, window dragging/resizing).
**Neither reproduced.**

One unrelated glitch did occur once: `cinnamon-screensaver` locked the
screen and then failed to unlock, dropping back to the LightDM greeter
instead. `journalctl -p err` showed the actual cause:

```
cinnamon-screensaver-pam-helper[...]: pam_unix(cinnamon-screensaver:auth): conversation failed
cinnamon-screensaver-pam-helper[...]: pam_unix(cinnamon-screensaver:auth): auth could not identify password for [user]
```

`cat /proc/sys/kernel/tainted` read `0` and there was no oops anywhere in
`dmesg` — this was **not** a kernel/driver crash (contrast with section
5's `TAINT_DIE`-tainted, oops-logged `i915` crash). Logging in again at the
greeter worked immediately. Reads as a one-off Cinnamon/PAM timing glitch,
unrelated to this repo's hardware-specific bugs.

**Given this**: clean RAM plus no reproduction of either bug under
deliberate testing is evidence (not proof — this was one test session, not
extended stress-testing) that sections 4-5 on unit 1 were more likely
RAM-corruption symptoms than universal firmware/driver bugs on this board.
The two community bug reports linked in section 4 still stand on their own
merits for other affected units, though.

### Unit 2 status

Healthy so far: firmware flashed, Debian 13 + Cinnamon running, RAM
confirmed clean, neither of unit 1's headline bugs reproduced under direct
testing. Credentials were set to real values directly during the Debian
install (not a vendor-set default), so `scripts/harden-default-credentials.sh`
doesn't apply the way it did for the sibling repo's pre-built-image
install method — there's no default credential here to harden.

Still worth watching with extended real-world use rather than considered
fully closed:
- The touchpad and `i915` crash paths were only exercised under short,
  deliberate testing, not extended daily use.
- Whether the NVRAM boot-entry flakiness from unit 1's section 2 recurs
  under different conditions (e.g. after firmware updates, NVRAM clears).

## Diagnostics cheat sheet

Useful commands if you're debugging similar territory:

```sh
# confirm firmware/board identity from the running kernel
dmesg | grep -i "Hardware name"          # e.g. "GOOGLE Celes/Celes, BIOS MrChromebox-..."

# confirm this is genuinely 64-bit hardware before trusting a memtest86+ result
lscpu | grep -E "Architecture|Model name|CPU op-mode"
uname -a

# check a specific IRQ's fire count (watch this climb during touchpad testing)
grep -i atml /proc/interrupts

# check whether a device's calibration/config firmware actually loaded
dmesg | grep -i "failed to load"

# check kernel taint state (128 = TAINT_DIE, a previous oops happened; 0 = clean)
cat /proc/sys/kernel/tainted

# is a hung process stuck in the kernel (D state) rather than just slow?
ps aux | grep ' D '

# list boots and jump into a specific one's log (e.g. -1 = previous boot)
journalctl --list-boots
journalctl -b -1 --no-pager

# GPU frequency scaling state (i915)
cat /sys/class/drm/card0/gt_min_freq_mhz
cat /sys/class/drm/card0/gt_max_freq_mhz
cat /sys/class/drm/card0/gt_cur_freq_mhz

# zswap current config
cat /sys/module/zswap/parameters/enabled
cat /sys/module/zswap/parameters/max_pool_percent
cat /sys/module/zswap/parameters/compressor
```

## Repo contents

- [`scripts/disable-atmel-touchpad.sh`](scripts/disable-atmel-touchpad.sh)
  — unbind the Atmel maXTouch touchpad driver live and blacklist it so it
  won't load on future boots either, for when it's hard-locking the
  machine (section 4) and a USB mouse is available as a workaround.
- [`scripts/install-memtest86-grub-entry.sh`](scripts/install-memtest86-grub-entry.sh)
  — install `memtest86+` and make sure the GRUB menu actually stays
  visible long enough to select it (Debian's default is a short/hidden
  timeout that's easy to miss).
- [`scripts/harden-default-credentials.sh`](scripts/harden-default-credentials.sh)
  — interactively change a weak default account password. Adapted from
  the sibling repo's script of the same name; never got applied here
  before the RAM finding took priority — do this early on the next unit.
