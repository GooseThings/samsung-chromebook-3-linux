# Linux on a Samsung Chromebook 3 (XE500C13)

Prep notes for getting Debian + Cinnamon running on a Samsung Chromebook 3
(XE500C13, Intel Celeron N3060 "Braswell", coreboot + depthcharge firmware).
**The device hasn't arrived yet** — this repo currently holds the plan, to
be replaced/expanded with the real diagnostic write-up once it's in hand.

For the sibling project on a different (ARM) Chromebook, see
[`samsung-chromebook-2-linux`](https://github.com/GooseThings/samsung-chromebook-2-linux).
Most of that hardware-specific work does **not** carry over to this Intel
board — see `CLAUDE.md` for exactly what does and doesn't transfer.

## Hardware

- Samsung Chromebook 3 — XE500C13
- SoC: Intel Celeron N3060 (Braswell)
- Firmware: coreboot + depthcharge (standard for this era of Intel
  Chromebook — unlike the U-Boot-based ARM sibling device, no known vboot
  signing limitation is expected here)

## Plan

1. **Enable Developer Mode** (`Esc+Refresh+Power`, then `Ctrl+D`) —
   powerwashes the device.
2. **Flash MrChromebox firmware** (`mrchromebox.tech/firmware.sh`) from a
   ChromeOS root shell (`crosh` → `shell`), replacing stock firmware with
   real UEFI/SeaBIOS. Chose this over the Ctrl+L legacy-boot-every-time
   route for a normal, permanent boot experience.
   - Write-protect screw location for this specific model revision needs
     confirming against MrChromebox's own device page or a teardown guide
     before opening the case — not assumed from memory.
3. **Install Debian** via a normal x86 installer USB (no ARM-style image
   builder needed here).
4. **Desktop environment**: Cinnamon, matching the sibling Chromebook.
5. **Post-install hardening/tuning**: change default credentials
   immediately, and re-derive appropriate power-tuning settings for this
   hardware (don't copy the ARM sibling's GPU-devfreq-pin or CPU-cap values
   — those were specific to a Mali GPU flicker bug that has no reason to
   exist on Intel graphics).

## Status

Not started — waiting on hardware.
