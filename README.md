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

**A second unit has since arrived and passed `memtest86+` cleanly** — see
[Unit 2](#unit-2-2026-09-25) below. It has its own, real `i915` display
bug (Unit 2 sections 11, 15, 16), unrelated to unit 1's RAM failure.
Unit 1's writeup is kept intact as-is.

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

Section numbering restarts at 1 here. Within this Unit 2 part, a bare
"section N" means Unit 2's section N; unit 1's are always written out as
"Unit 1 section N".

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
(Unit 1 section 2), skipping the live-Cinnamon/Calamares path entirely. Installed
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

Per unit 1's explicit lesson (Unit 1 section 8, `CLAUDE.md` priority #2),
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
The two community bug reports linked in Unit 1 section 4 still stand on their own
merits for other affected units, though.

**Update, later the same session**: the `i915` conclusion above didn't
hold up under further use — see Unit 2 section 11. A real, reproducible display
bug did show up under GPU load; it just wasn't the fatal, oops-and-taint
crash from Unit 1 section 5. The touchpad hard-lock still hasn't reproduced.

### 10. Power tuning — two settings that don't survive reboot on their own

Applied [`scripts/tune-power-settings.sh`](scripts/tune-power-settings.sh),
adapted from the sibling repo's script of the same name: TLP (with
`schedutil` pinned for AC and battery — already the kernel default here,
but pinned explicitly so nothing silently reverts it), zswap (`zstd`, 30%
pool) with `vm.swappiness=100`, and the Bluetooth radio disabled. The
sibling script's GPU devfreq pin was deliberately **not** carried over —
that worked around a Mali/Panfrost flicker bug specific to that board's ARM
GPU, with no equivalent on this board's Intel `i915` driver.

Two settings silently didn't stick across a reboot, both confirmed by
actually rebooting and re-checking rather than trusting the apply step:

- **`zswap.compressor=zstd` on the kernel cmdline fell back to `lzo`.**
  `cat /sys/module/zswap/parameters/compressor` read `lzo` after reboot
  despite the cmdline param being present in `/proc/cmdline` exactly as
  set. Root cause: zswap's compressor param is applied very early in boot
  — before the `zstd` module can autoload — so it silently falls back to
  whatever's already available rather than erroring. Re-writing the sysfs
  param (`echo zstd > .../compressor`) after boot works fine once the
  module is actually loaded.
- **`rfkill block bluetooth` didn't survive reboot either** — it's a live
  kernel-state change, not persistent config, and the systemd component
  that would normally persist it (`systemd-rfkill`) is **masked** on this
  image.

Fixed both the same way: a `zstd` entry in `/etc/modules-load.d/` plus a
oneshot systemd service (`power-tuning-boot-fixup.service`, installed by
the script) that re-applies `modprobe zstd; echo zstd >
.../compressor` and `rfkill block bluetooth` once boot reaches
`multi-user.target`, rather than unmasking a system-wide service just for
this. Confirmed post-reboot: `zswap` enabled with `zstd`/30%,
`vm.swappiness=100`, governor `schedutil`, Bluetooth soft-blocked, `tlp`
active — all holding after a real reboot, not just immediately after
applying.

### 11. `i915` display corruption under GPU load — real bug, different from unit 1's, has a fix

Shortly after the power-tuning reboot: screen flickering, then black with
flickering white lines at the top, no visible cursor. Ruled out in order,
citing actual output at each step rather than guessing:

- **Not a full hard-lock** (unlike Unit 1 section 4's touchpad bug) — the machine
  stayed reachable over SSH throughout every occurrence.
- **Not TLP** — `systemctl stop tlp.service` while it was happening had no
  effect.
- **Not zswap/swappiness** — `/sys/kernel/debug/zswap` showed 0 stored
  pages and `free -h` showed 0 swap used at the time; it wasn't even active.
- **Not a loose cable from the WP-screw teardown** — physically checked,
  connectors were fully seated.
- **Not unit 1's fatal crash** — `cat /proc/sys/kernel/tainted` read `0`
  every time, `Xorg` stayed alive and out of `D` state, and
  `systemctl restart display-manager.service` (which would at least
  temporarily help a userspace-level glitch) did nothing. Unit 1's section
  5 crash always left a `TAINT_DIE`-tainted kernel oops behind; this
  never did.
- **A full reboot did clear it**, temporarily — until reproduced again
  reliably by opening Firefox and playing a YouTube video (the same
  "compositor/video load" trigger Unit 1 section 5 speculated about). `dmesg`
  caught the actual mechanism on a couple of occurrences:
  ```
  i915 0000:00:02.0: [drm] *ERROR* pipe A underrun
  i915 0000:00:02.0: [drm] *ERROR* CPU pipe A FIFO underrun
  ```
  A display-pipe FIFO underrun — the panel not getting fed data fast
  enough — which is a real, known category of bug on Cherryview `i915`
  hardware, distinct from Unit 1 section 5's NULL-pointer page-flip oops. It's
  also not reliably logged: some occurrences produced these lines, at
  least one produced nothing in `dmesg` at all despite the same visible
  corruption, so absence of this exact log line doesn't rule the bug out.

**Root cause and fix**: checked panel self-refresh (PSR) status via
`/sys/kernel/debug/dri/0000:00:02.0/i915_params/enable_psr`, which read
`-1` (driver default — effectively on for a supported panel). PSR
misbehaving under load is a well-documented real-world source of exactly
this kind of corruption on Intel platforms. Added `i915.enable_psr=0` to
`GRUB_CMDLINE_LINUX_DEFAULT`, ran `update-grub`, rebooted, confirmed
`enable_psr` read `0`, then repeated the exact same Firefox+YouTube test
that reliably triggered it before. **No crash, no flicker.** (FBC was
already off by default on this platform — Cherryview doesn't support it —
so PSR was the only power-saving display feature left to suspect.)

**Update, a later session**: this fix only ever covered the one trigger
it was tested against. The same visible symptom came back under
completely different triggers (see section 15) and survived every
further mitigation tried, including ones that should have been more
fundamental than PSR. Leaving this section's own account intact since the
PSR fix was real and reproducible for what it covered — just don't read
"no crash, no flicker" as the end of the story.

### 12. Top-row action keys send no scancode at all — a firmware/EC gap, not a Linux remap issue

Tried applying the sibling repo's function-row-remap technique
(the sibling repo's `scripts/fix-function-row-keys.sh` — not in this
repo — / hwdb `KEYBOARD_KEY_*` overrides) and
it doesn't apply here, for a more fundamental reason than just "different
scancodes":

- This board's only keyboard input device is `"AT Translated Set 2
  keyboard"` via `i8042`/`serio0` — legacy PS/2, not the sibling's
  `cros_ec` SPI matrix keyboard. Different bus entirely, so the sibling's
  hwdb match line and captured codes were never going to transfer as-is
  (as `CLAUDE.md` already anticipated) — but the actual finding goes
  further.
- Captured with `evtest` on `/dev/input/event0` across three separate,
  carefully-timed windows: **zero events** of any kind for any top-row
  key, not even `EV_MSC`/`MSC_SCAN`.
- Checked for the `atkbd` driver's own "Unknown key" warning (which fires
  in `dmesg` when a scancode arrives that the driver's table doesn't
  recognize — this is exactly the hook `KEYBOARD_KEY_*` hwdb overrides
  patch into). **Nothing.** No scancode is reaching the OS at all, not
  even an unrecognized one.
- MrChromebox's Full ROM flash only reflashes the AP (application
  processor) firmware; the separate embedded controller (EC) chip that
  physically scans the keyboard matrix still runs its original stock
  ChromeOS EC firmware, untouched. `cros_ec`/`cros_ec_lpcs` (the AP↔EC
  communication transport) are loaded and clearly working — `cros-ec-hwmon`,
  `cros-ec-led`, `cros-charge-control` etc. all function. Manually
  `modprobe cros_ec_keyb` (the actual driver that turns EC keyboard-matrix
  scan events into real ChromeOS action-key codes) loads cleanly into the
  kernel with no errors — but creates no input device, because **there is
  no matching child device under the EC's platform device tree at all**
  (`find /sys/bus/platform/devices/cros-ec-dev.1.auto/` lists `hwmon`,
  `gpio`, `charge-control`, `chardev`, `sysfs`, `debugfs`, `led` — no
  `keyb`).

**Conclusion**: this traces to coreboot itself, not Linux. Coreboot
generates the ACPI tables that tell the kernel which EC sub-devices exist;
for this board's coreboot port, no keyboard-matrix child device is
declared at all. A web search turned up the likely explanation directly:
MrChromebox's EC-level keyboard fix (which is what makes these keys work
automatically with zero Linux-side config on other boards) was added for
**APL, GLK, and CML** platforms — Braswell (this board's platform) isn't
in that list.

Actually fixing this would mean patching coreboot's ACPI/SSDT generation
for the `celes` board and building a custom firmware image from source —
real coreboot development, well beyond a Linux config change, and out of
scope for now. Documented as a known limitation rather than pursued
further. Workarounds: browser back/forward via `Alt+Left`/`Alt+Right`,
brightness/volume via Cinnamon's own OSD/system tray, or a USB keyboard
(bypasses the AT/PS2 EC path entirely) if the built-in keys are needed.

### 13. Ham radio and general software installed

Straightforward installs, noted here mainly for the gotchas:

- **[MSHV](https://github.com/LZ2HV/MSHV)** (weak-signal digital mode
  decoder) — no prebuilt Linux binary exists upstream (Windows-only
  releases); it does have genuine native Linux support via Qt5/qmake,
  though. Built from source: `qtbase5-dev`, `qt5-qmake`, `libasound2-dev`,
  `libfftw3-dev`, `libpulse-dev`, `libqt5websockets5-dev`,
  `libqt5serialport5-dev`, then `qmake MSHV_x86_64.pro && make` — compiles
  clean on Debian 13's packages with no source changes needed. Slow on
  this CPU (~10 minutes for ~150 files) but works.
- **[Pat](https://getpat.io/)** (Winlink client) — installed the upstream
  GitHub release `.deb` (v1.0.0) over Debian's own older packaged version
  (0.16.0); `apt install ./pat_*.deb` upgrades it in place cleanly.
- **flrig** (rig control) — directly in Debian's repos, plain
  `apt install flrig`.
- **Discord**, **GridTracker 2** — official `.deb` packages from each
  vendor's own site, both installed clean.
- **HAMRS** (portable-ops logging) — Linux build is AppImage-only (no
  `.deb`, unlike GridTracker). Failed on first launch with `dlopen():
  error loading libfuse.so.2` — Debian 13 doesn't install FUSE2 by
  default anymore (only `fuse3`). Fixed with `apt install libfuse2t64`
  (the time_t-transition-renamed compat package); AppImage FUSE-mounts
  and runs normally after that.

### 14. Pat's web config UI wouldn't save — browser-side, never conclusively root-caused

Set a callsign in Pat's web UI (`localhost:8080`); it silently didn't
persist, and the mailbox stayed locked behind the "missing mycall" guard.
Isolated methodically:

- Restarted Pat with its output captured to a log file instead of an
  interactive terminal, to actually see what happened server-side on a
  save attempt — no request of any kind logged.
- Tested the backend directly: `curl -X PUT http://localhost:8080/api/config
  -d '{"mycall":"TEST1"}'` — saved instantly, confirmed via
  `~/.config/pat/config.json`. **The backend works fine.** The browser's
  save action either wasn't firing the request at all, or something
  client-side (Brave's Shields, a JS error) was swallowing it.
- **Gotcha discovered doing this**: `/api/config`'s `PUT` is a full
  replace, not a merge. A follow-up curl call sending only `{"mycall":""}`
  to "reset" the test value wiped every other field in the config
  (`ax25.engine`, `http_addr`, `service_codes`, etc. all went blank/zero),
  and returned `500 invalid AX.25 engine ''` — after already writing the
  broken file to disk. The real web frontend avoids this by always
  submitting the entire loaded config object back, not a partial one;
  don't shortcut-test this API with partial JSON bodies. Recovered by
  deleting `config.json` entirely and letting Pat regenerate its own
  clean defaults on next start, rather than hand-reconstructing it.
- Never identified the actual browser-side cause. The user reported it
  "just worked" on a later attempt, callsign saved successfully and
  confirmed via the same `config.json` inspection. Filed here as an
  unresolved, self-resolved glitch rather than a confirmed fix.

### 15. The `i915` display bug is back, worse than thought — four more mitigations, all failed

Section 11's PSR fix turned out to only cover the one trigger it was
tested against (Firefox + video). The same visible symptom (flicker,
black screen, garbage lines, no cursor) came back repeatedly under
completely different triggers — Discord loading and being clicked
around in, and a plain logout to the LightDM greeter — with `i915.enable_psr=0`
still confirmed active the entire time. Every further mitigation tried
also failed, each ruled out with direct evidence rather than assumption:

- **Discord's own GPU use** — launched with `--disable-gpu
  --disable-accelerated-video-decode --disable-accelerated-video-encode
  --disable-features=VaapiVideoDecoder,VaapiVideoEncoder`. Confirmed via
  `fuser -v /dev/dri/*` that Discord held **zero** GPU file descriptors at
  all (no `card0`, no `renderD128`) — genuinely fully off the GPU. Bug
  recurred anyway.
- **Xorg's own rendering backend** — `/etc/X11/xorg.conf.d/` snippet
  forcing `Option "AccelMethod" "none"`. Confirmed via `Xorg.0.log`:
  `glamor disabled`, `ShadowFB: enabled YES` — genuine software-only X
  server rendering. Bug recurred anyway. (Reverted afterward — real
  performance cost, zero benefit.)
- **Display C-states** — `i915.enable_dc=0` (disables the display
  engine's DMC-managed power states, a different mechanism than PSR).
  Confirmed active via `/proc/cmdline`. Bug recurred anyway.
- **Xorg's scheduling priority** — `chrt -r -p 10 <Xorg pid>`, live on the
  running process, on the theory that a display-commit deadline miss
  under CPU/memory contention was the mechanism (see below). Confirmed
  via `chrt -p` before/after. Bug recurred anyway, caught live by a
  `Monitor`-based `dmesg -w` watch running during the reproduction
  attempt.
- **Out-of-memory exhaustion** — checked `dmesg`/`journalctl -b 0` for any
  `Out of memory: Killed process` or page-allocation-failure line across
  the whole boot. **None.** This isn't the system running out of memory
  capacity and OOM-killing things.

What actually correlated, every time checked: low free memory (as little
as 120MB free of 3.8GB, swap actively in use) at the moment of each
recurrence, and two new, more specific error signatures beyond section
11's plain FIFO underrun:

```
i915 0000:00:02.0: [drm] *ERROR* Atomic update failure on pipe A (start=42033 end=42034) time 5 us, min 763, max 767, scanline start 750, end 768
i915 0000:00:02.0: [drm] *ERROR* Unexpected PHY_STATUS 0x80000000, expected 0x800001f8 (PHY_CONTROL=0x050007fd)
```

The first is an explicit real-time deadline miss on the display commit —
consistent with (though not proven caused by) heavy simultaneous memory
pressure from running Discord and a many-tabbed Firefox session together
on a 3.8GB machine, exactly the condition present at the time. The second
is a different kind of error entirely: a hardware-level status-register
mismatch on the display's DPIO PHY (the physical layer driving the eDP
signal lanes), a genuinely lower-level symptom than anything else logged
tonight, and not something any rendering, compositor, or scheduling
change could plausibly reach.

**Where this stands**: unresolved. There's no alternative driver to try —
`i915` is the only graphics driver Cherryview has ever had on Linux, open
or closed. VLV/CHV's display PHYs are a documented peculiar area of this
driver (sideband-controlled, not plain MMIO, with specific clock-sequencing
requirements), and the exact function behind that PHY_STATUS check
(`vlv_wait_port_ready()`) was still being refactored upstream as recently
as February 2025 — a newer kernel than Debian's stock 6.12.107 is a real,
untried option, at the cost of losing a clean apt-managed kernel. The
extended, multi-pass `memtest86+` run (beyond Unit 2 section 7's single quick
clean pass) is also still outstanding, and worth doing given the
memory-pressure correlation above, even without direct hardware-error
evidence (no MCE, no EDAC report, no OOM-kill) found tonight.

Two smaller, unrelated findings from the same log review, worth a
one-line note each: `soundmodem.service` fails to start
("Configuration not found") — a leftover dependency of the `pat`/
`ax25-tools` install, unconfigured and unused so far, harmless but worth
cleaning up eventually; and the `cinnamon-screensaver` PAM glitch from
section 9 recurred a second time tonight, still one-off and still not
further investigated.

### 16. A GPU-frequency-scaling angle from the sibling repo — genuinely promising, initially masked by an unrelated bug — plus a full system hang that turned out to be real memory exhaustion

The sibling Chromebook 2 repo has an almost exact parallel to this whole
saga (its own section 6): intermittent panel flicker/blink-to-black,
initially blamed on CPU/GPU load, actually caused by the Mali GPU's
`devfreq` **frequency-scaling transitions themselves** (not the frequency
level — both a fixed-low and fixed-high pin worked equally well) glitching
a voltage rail shared with the panel. `i915` has an analogous mechanism
(RPS — automatic render-engine frequency scaling), never tried here
before tonight:

- **Pinned RPS live via sysfs** (`gt_min_freq_mhz` = `gt_max_freq_mhz` =
  320, the hardware's `RP1`/"efficient" rated point — no reboot needed).
  One slight black-screen flash while Discord loaded right after applying
  it, then stable for an extended stretch afterward, including under
  combined Discord + Firefox + YouTube load with memory tight again — the
  best stretch of stability all night, but correlational, not proven,
  given the bug's established intermittency.
- **`i915.disable_power_well=0`** (forces display power wells to stay up)
  added and confirmed active at the module-parameter level afterward. But
  `/sys/kernel/debug/dri/.../gt0/drpc` still showed the GT's own
  render/media power wells cycling through RC6 exactly as before — this
  parameter most likely governs the *display* pipe's power wells, a
  related but architecturally separate domain from the GT engine's own
  RC6 power gating, so it probably never touched the actual mechanism.
  There's no `i915.enable_rc6` override left in this kernel version
  (removed upstream at some point) to test RC6 more directly.

**Update, later the same session**: at the time, neither test looked
conclusively proven — a "slight black screen" and later reports of
"crashing" kept showing up after applying these, with zero corresponding
`i915` errors each time, which read as the driver just not logging it.
The real explanation turned out to be simpler and better: **there has
been no new `i915` error of any kind (no FIFO underrun, no atomic-update
failure, no PHY_STATUS mismatch) since the GPU frequency pin was
applied** — not once, across several hours including the exact
Discord/Firefox/YouTube combinations that reliably triggered it earlier.
Every "crash" reported after that point turned out to be one of two
entirely separate, unrelated bugs (the memory-exhaustion hang below, and
the screensaver PAM crash-loop in section 18) that happen to produce a
near-identical visible symptom (screen goes black, sometimes back to a
lock/password prompt). Once those two were independently diagnosed and
fixed, the absence of any further `i915` error becomes much more
meaningful — this is now the best evidence of the whole investigation
that the GPU-frequency-pin theory, borrowed from the sibling repo, might
actually be right. Still not conclusively proven (this board's own
history is full of quiet stretches that turned out to be coincidental),
but genuinely promising, and worth much longer soak testing before
calling it fixed.

**Separately, and initially confused with the same investigation**: while
testing a `vm.swappiness` change for responsiveness (section 17), the
machine went fully unresponsive — not just the display, but genuinely
unreachable over SSH too, unlike **every** other occurrence tonight,
which all stayed SSH-reachable throughout. Required a hard power-cycle to
recover. The persistent journal (confirmed already active by default —
`/var/log/journal` survives reboots without any changes needed) and the
resource-monitor CSV (the logger installed after section 15 — see
[`scripts/install-resource-monitor.sh`](scripts/install-resource-monitor.sh)) together reconstructed exactly what
happened, and it's a different failure mode from the `i915` bug entirely:

```
2026-09-26T16:21:38-04:00,2.78,5.53,5.54,3957092,216896,833596,280832,59309,30,...
```

That's the last sample before the freeze: free memory down to **~212MB**,
**~274MB of swap in use** (the log shows 0 swap used every sample from
midnight until 16:03, then climbing from there), zswap actively storing
compressed pages. Load average in that final sample was 2.78 / 5.53 /
5.54, but the log shows it had peaked at **15.91 / 11.01 / 5.81** at
16:12, nine minutes earlier — genuinely severe for a 2-core CPU. Right as this was unfolding, `iwlwifi` (the WiFi
driver) started repeatedly failing to submit commands to its own firmware
(`Error sending STATISTICS_CMD: enqueue_hcmd failed: -5`, `Failed to send
the temperature measurement command`) every few seconds for about two
minutes — then **all** logging stopped dead simultaneously (kernel log
and the resource-monitor's own CSV write, the latter caught mid-write with
null-byte padding, confirming the freeze happened *during* a write, not
just after). This was 29 open Firefox tabs plus Discord running
simultaneously — the same workload already flagged as the direct cause of
the "choppy" feel in section 17.

**How this fits with section 15**: section 15 ruled out *OOM-killing*
(no `Out of memory: Killed process` line anywhere), not memory pressure
itself — it actually found low free memory at every flicker recurrence.
This hang is a different, more severe failure mode on the same spectrum:
genuine memory exhaustion and swap thrashing under a heavier combined
workload than was running during the flicker-only occurrences, severe
enough that even unrelated
kernel-level periodic tasks (the WiFi chip's routine firmware polling)
started missing their timing and failing, cascading into a full hang. Not
a driver bug — a real hardware resource limit (3.8GB RAM, 2 weak cores)
being genuinely exceeded by the workload asked of it. This is also the
resource-monitor's first real payoff: precise, real data at the actual
moment of a failure, rather than a snapshot taken after the fact.

### 17. Getting more performance out of weak hardware

Reported as "a little choppy." Checked before changing anything:

```
Firefox (multiple processes): 46.5% + 36.7% + 20.0% + 8.9% CPU
Discord (multiple processes): 21.0% + 9.6% CPU
cinnamon: 12.5% CPU
```

— on a 2-core CPU with no hyperthreading, with **29 Firefox tabs** open
alongside Discord. This is genuine, legitimate CPU demand exceeding what
two weak cores can smoothly deliver, not a misconfiguration — no config
change makes a hardware ceiling disappear, and section 16's system hang
happened under exactly this kind of load.

Two real wins applied anyway, both live via `gsettings` (no restart
needed), reducing Cinnamon's own compositor overhead:

```sh
gsettings set org.cinnamon desktop-effects false
gsettings set org.cinnamon desktop-effects-on-menus false
gsettings set org.cinnamon desktop-effects-on-dialogs false
gsettings set org.cinnamon.muffin unredirect-fullscreen-windows true
```

The last one lets a maximized/fullscreen window (e.g. a fullscreen video)
bypass the compositor and scan out directly, rather than being composited
— worth having regardless of the animation/effects preference.

Also dialed `vm.swappiness` back from 100 (section 10's battery-life
choice) to the Debian default of **60**, trading some of that battery-life
tuning for responsiveness under load, at the user's explicit request. Real
trade-off, not a pure win — noted here so a future session doesn't
"re-fix" this back to 100 without knowing it was deliberate.
[`scripts/tune-power-settings.sh`](scripts/tune-power-settings.sh) now
writes 60 too, so re-running it doesn't silently undo this.

### 18. A completely separate bug masquerading as the `i915` crash: a broken PAM `account` stack crash-looping the screensaver

After section 16's GPU-frequency-pin experiment, "the screen goes black
and comes back" kept being reported — but this time with a distinct
pattern: it recovered on its own within moments, the machine never
stopped responding, and it sometimes landed on a lock screen asking for a
password, as if the machine had woken from sleep. That description alone
was the first clue this might not be the same bug at all — every real
`i915` occurrence all night either needed a full reboot or left visible
corruption; this didn't.

Ruled out the boring explanations first: X11 DPMS timeouts were actually
disabled (`0 0 0`), Cinnamon's own idle-lock is a 15-minute timer (`900`)
far longer than the ~30-90 second cycle actually being seen, and the user
confirmed they were **actively using the machine**, not idle, each time it
happened — ruling out any timeout-based explanation outright.

Caught it live with two parallel `Monitor` watches (one on `dmesg -w`,
one on `journalctl -f`, both filtered to new lines only) and found the
real mechanism: `org.cinnamon.ScreenSaver` was being repeatedly
D-Bus-activated, running briefly, and crashing (`Error in
sys.excepthook`, `Original exception was:` — the actual traceback itself
never made it into the journal, cut off both times it was checked),
every single occurrence paired with:

```
pam_unix(cinnamon-screensaver:account): setuid failed: Operation not permitted
```

— right after a *successful* password/keyring unlock, meaning
authentication itself was fine; it was PAM's **account** phase
specifically that was failing on every single cycle, crashing the
screensaver process and forcing a fresh D-Bus-activated relaunch (which
defaults to a locked state) each time — a genuine crash-loop, not a
timeout.

Investigated methodically, each one a real, ruled-out hypothesis rather
than a guess:

- **Missing `@include common-account`** — confirmed real:
  `/etc/pam.d/cinnamon-screensaver` had only `common-auth` and a
  `pam_gnome_keyring.so` line, unlike `/etc/pam.d/lightdm`'s full stack
  (`common-auth`, `common-account`, `common-session`, `common-password`).
  Added it (backup kept at `cinnamon-screensaver.bak`). **Didn't fix it**
  — identical error recurred immediately after.
- **`NoNewPrivileges`-style privilege stripping** — the modern, common
  cause of a legitimately-setuid-root helper (`unix_chkpwd`, confirmed
  correctly `-rwxr-sr-x root shadow` on this system) silently losing its
  privilege escalation. Checked `/proc/<pid>/status` on the actual live
  screensaver process: `NoNewPrivs: 0`. Not this either.
- **Missing capability/setuid bit on `cinnamon-screensaver-pam-helper`
  itself** — checked `getcap` (nothing set) and the package's `postinst`
  script (no `chmod`/`setcap` step referencing it at all) — inconclusive
  either way, but nothing obviously missing from the packaging.
- **Tried to capture the actual Python traceback directly**, bypassing
  journald, by launching `cinnamon-screensaver` manually with
  stdout/stderr redirected straight to a file. Lost it anyway — the
  process crashed hard enough to exit without flushing its (fully
  buffered, since redirected to a file rather than a TTY) output buffer,
  losing the exact exception text a second time.

**Root cause not conclusively identified** — this needs a real debugger
(`gdb`/`strace` attached before the crash, or `PYTHONUNBUFFERED=1` set
*in advance* of the triggering event) rather than more guessing after the
fact over SSH. Given this was actively disrupting normal use every
30-90 seconds, stopped chasing it live and applied a direct mitigation
instead:

```sh
gsettings set org.cinnamon.desktop.screensaver lock-enabled false
gsettings set org.cinnamon.desktop.session idle-delay 0
gsettings set org.cinnamon.settings-daemon.plugins.power sleep-display-ac 0
gsettings set org.cinnamon.settings-daemon.plugins.power sleep-display-battery 0
```

Screensaver/auto-lock/display-sleep fully disabled. Confirmed no
recurrence afterward. **Trade-off, not a fix**: there is currently no
automatic screen lock on this machine at all — acceptable for a personal
device, worth revisiting (with real debugging tools, not SSH guesswork)
before this device is ever used somewhere an unattended unlocked screen
would matter.

### Unit 2 status

Mostly running well, but with one real open problem. Firmware flashed,
Debian 13 + Cinnamon running, RAM's single quick pass came back clean,
power tuning applied and verified across a reboot, ham radio and general
software installed. The touchpad hard-lock (unit 1 section 4) hasn't
reproduced. The top-row action keys don't work and are a documented
firmware/EC limitation (section 12), not something Linux-side can fix.
Credentials were set to real values directly during the Debian install
(not a vendor-set default), so `scripts/harden-default-credentials.sh`
doesn't apply the way it did for the sibling repo's pre-built-image
install method — there's no default credential here to harden.

**Three separate problems surfaced tonight, easy to conflate since two of
them look almost identical to the naked eye ("screen goes black").
Keeping them straight matters:**

1. **The `i915` display-corruption bug** (sections 11, 15, 16) — genuinely
   promising after pinning the GPU's RPS frequency to 320MHz: **zero**
   new `i915` errors of any kind since that change, across several hours
   including the exact conditions that reliably triggered it before. Not
   conclusively proven (needs much longer soak testing), but the best
   evidence yet that it's actually working, borrowed directly from the
   sibling repo's own near-identical GPU-devfreq bug. Before this, it had
   only partly yielded to PSR-off (section 11) and survived four other
   mitigations across every layer of the stack (app GPU use, Xorg's
   rendering backend, display C-states, Xorg's scheduling priority).
   To keep the soak test clean, the kernel parameters that were tried and
   didn't help (`i915.enable_dc=0`, `i915.disable_power_well=0`) were
   removed afterward, leaving only `i915.enable_psr=0` plus the RPS pin —
   see [`scripts/set-i915-kernel-params.sh`](scripts/set-i915-kernel-params.sh).
   Untried next steps if the pin doesn't
   hold up: a newer kernel than Debian's stock 6.12.107 (the exact
   PHY-readiness code saw upstream changes as recently as February 2025),
   and a longer multi-pass `memtest86+` run (only one quick clean pass
   has ever been done).
2. **A full system hang under genuinely heavy load** (29 Firefox tabs +
   Discord simultaneously) — confirmed via the resource-monitor log to be
   real memory exhaustion and swap-thrashing (~212MB free, ~274MB swap in
   use, 1-minute load average peaking at 15.9 on this 2-core CPU), not a
   driver bug. A
   hardware resource ceiling, not something to chase a fix for — the
   mitigation is not running that much simultaneously, which section 17's
   performance-tuning work also points at directly.
3. **A broken PAM `account` stack crash-looping the Cinnamon screensaver**
   (section 18) — repeatedly misread mid-session as the `i915` bug
   recurring, since both present as "screen goes black, sometimes to a
   lock prompt." Root cause not conclusively identified (needs a real
   debugger, not more SSH guesswork), mitigated by disabling the
   screensaver/auto-lock entirely. **This means there is currently no
   automatic screen lock on this machine at all** — a real trade-off, not
   a clean fix, worth revisiting before this device is used anywhere an
   unattended unlocked screen would matter.

Still worth watching with extended real-world use rather than considered
fully closed:
- The touchpad hard-lock path was only exercised under short, deliberate
  testing, not extended daily use — it hasn't shown up yet, but that's
  not the same as ruling it out.
- Whether the RPS frequency pin genuinely fixed the `i915` bug or just
  got lucky over one evening — needs much longer soak testing, now that
  the two confounding bugs above are understood and out of the way.
- The screensaver PAM crash-loop's actual root cause, and whether
  automatic locking should be re-enabled once it's properly fixed.
- Whether the NVRAM boot-entry flakiness from unit 1's section 2 recurs
  under different conditions (e.g. after firmware updates, NVRAM clears).
- `soundmodem.service` fails to start (section 15) — unconfigured
  leftover from the `pat` install, harmless but unresolved.

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

# recent i915 display errors (FIFO underrun, atomic update failure, PHY_STATUS)
sudo dmesg | grep -iE 'i915.*ERROR|underrun|PHY_STATUS'

# which processes hold GPU file descriptors (is an app really off the GPU?)
sudo fuser -v /dev/dri/*

# i915 panel self-refresh (PSR) state -- suspect #1 for flicker/corruption under load
cat /sys/kernel/debug/dri/0000:00:02.0/i915_params/enable_psr   # -1 = driver default (on), 0 = disabled

# does the EC expose a given sub-device (e.g. keyboard-matrix) to the kernel at all?
find /sys/bus/platform/devices/cros-ec-dev.*.auto/ -maxdepth 1

# capture raw keyboard scancodes to check what a key actually sends (if anything)
sudo evtest /dev/input/event0   # then press the key in question
```

## Repo contents

- [`scripts/disable-atmel-touchpad.sh`](scripts/disable-atmel-touchpad.sh)
  — unbind the Atmel maXTouch touchpad driver live and blacklist it so it
  won't load on future boots either, for when it's hard-locking the
  machine (Unit 1 section 4) and a USB mouse is available as a workaround.
- [`scripts/install-memtest86-grub-entry.sh`](scripts/install-memtest86-grub-entry.sh)
  — install `memtest86+` and make sure the GRUB menu actually stays
  visible long enough to select it (Debian's default is a short/hidden
  timeout that's easy to miss).
- [`scripts/harden-default-credentials.sh`](scripts/harden-default-credentials.sh)
  — interactively change a weak default account password (defaults to the
  current user; prompts twice, refuses empty). Adapted from the sibling
  repo's script of the same name. Only needed when the install method
  leaves a default password behind — unit 1 never got to it before the RAM
  finding, and unit 2's netinst install set real credentials directly, so
  it didn't apply there (see Unit 2 status).
- [`scripts/tune-power-settings.sh`](scripts/tune-power-settings.sh) —
  battery-life tuning (TLP/`schedutil`, zswap+swappiness, Bluetooth
  disable). Adapted from the sibling repo's script of the same name, minus
  its Mali-specific GPU devfreq pin; also installs a boot-time fixup
  service for two settings that don't survive reboot on their own — see
  Unit 2 section 10. Writes `vm.swappiness=60`, not the original 100 —
  see Unit 2 section 17.
- [`scripts/set-i915-kernel-params.sh`](scripts/set-i915-kernel-params.sh)
  — idempotently sets `i915.enable_psr=0` (Unit 2 section 11's real fix)
  on the kernel command line and removes the `i915.enable_dc=0` /
  `i915.disable_power_well=0` experiments that didn't help (sections
  15-16).
- [`scripts/install-resource-monitor.sh`](scripts/install-resource-monitor.sh)
  — installs [`scripts/system-resource-monitor.sh`](scripts/system-resource-monitor.sh)
  as a continuous systemd service, logging load/memory/swap/zswap/CPU
  frequency/thermal state to a rotating daily CSV
  (`/var/log/resource-monitor/`) every 5s. Written to give the still-open
  `i915` display bug (Unit 2 section 15) an actual history to check against
  instead of only whatever gets checked by hand in the moment. Already
  paid off once — see Unit 2 section 16.
- [`scripts/install-i915-gpu-freq-pin.sh`](scripts/install-i915-gpu-freq-pin.sh)
  — installs [`scripts/pin-i915-gpu-freq.sh`](scripts/pin-i915-gpu-freq.sh)
  as a boot-time service pinning the GPU's RPS frequency scaling to a
  fixed 320MHz, on the sibling repo's GPU-devfreq-transition theory (see
  Unit 2 section 16). Unproven experiment, not a confirmed fix.
