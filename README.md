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

**Update, later the same session**: the `i915` conclusion above didn't
hold up under further use — see section 11. A real, reproducible display
bug did show up under GPU load; it just wasn't the fatal, oops-and-taint
crash from section 5. The touchpad hard-lock still hasn't reproduced.

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

- **Not a full hard-lock** (unlike section 4's touchpad bug) — the machine
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
  "compositor/video load" trigger section 5 speculated about). `dmesg`
  caught the actual mechanism on a couple of occurrences:
  ```
  i915 0000:00:02.0: [drm] *ERROR* pipe A underrun
  i915 0000:00:02.0: [drm] *ERROR* CPU pipe A FIFO underrun
  ```
  A display-pipe FIFO underrun — the panel not getting fed data fast
  enough — which is a real, known category of bug on Cherryview `i915`
  hardware, distinct from section 5's NULL-pointer page-flip oops. It's
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
(`scripts/fix-function-row-keys.sh` / hwdb `KEYBOARD_KEY_*` overrides) and
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

### 15. The `i915` display bug is back, worse than thought — five more mitigations, all failed

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
extended, multi-pass `memtest86+` run (beyond section 7's single quick
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

**The open problem**: the `i915` display-corruption bug (section 11, then
section 15) is not actually fixed. PSR-disable genuinely fixed its own
trigger, but the same symptom keeps coming back under other triggers and
has now survived five distinct mitigations across every layer of the
stack — app GPU use, Xorg's own rendering backend, two different kernel
display power features, and Xorg's own scheduling priority. Current
best guess is a genuine PHY-level fragility in this Cherryview board's
display driver, possibly correlated with memory pressure, not fixable
with a config flag. Untried next steps: a newer kernel than Debian's
stock 6.12.107 (this exact PHY-readiness code saw upstream changes as
recently as February 2025), and a longer multi-pass `memtest86+` run
(only a single quick clean pass has been done so far, and every
recurrence tonight coincided with low free memory).

Still worth watching with extended real-world use rather than considered
fully closed:
- The touchpad hard-lock path was only exercised under short, deliberate
  testing, not extended daily use — it hasn't shown up yet, but that's
  not the same as ruling it out.
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
  machine (section 4) and a USB mouse is available as a workaround.
- [`scripts/install-memtest86-grub-entry.sh`](scripts/install-memtest86-grub-entry.sh)
  — install `memtest86+` and make sure the GRUB menu actually stays
  visible long enough to select it (Debian's default is a short/hidden
  timeout that's easy to miss).
- [`scripts/harden-default-credentials.sh`](scripts/harden-default-credentials.sh)
  — interactively change a weak default account password. Adapted from
  the sibling repo's script of the same name; never got applied here
  before the RAM finding took priority — do this early on the next unit.
- [`scripts/tune-power-settings.sh`](scripts/tune-power-settings.sh) —
  battery-life tuning (TLP/`schedutil`, zswap+swappiness, Bluetooth
  disable). Adapted from the sibling repo's script of the same name, minus
  its Mali-specific GPU devfreq pin; also installs a boot-time fixup
  service for two settings that don't survive reboot on their own — see
  Unit 2 section 10.
- [`scripts/install-resource-monitor.sh`](scripts/install-resource-monitor.sh)
  — installs [`scripts/system-resource-monitor.sh`](scripts/system-resource-monitor.sh)
  as a continuous systemd service, logging load/memory/swap/zswap/CPU
  frequency/thermal state to a rotating daily CSV
  (`/var/log/resource-monitor/`) every 5s. Written to give the still-open
  `i915` display bug (section 15) an actual history to check against
  instead of only whatever gets checked by hand in the moment.
