# Project context for Claude

This repo documents getting Linux running well on a **Samsung Chromebook 3
(XE500C13)** — Intel Celeron N3060 (Braswell), MrChromebox Full ROM
(UEFI/edk2) firmware. The first unit has already arrived, been fully
diagnosed, and retired — `memtest86+` found severe soldered-RAM failure
(3000 then 8314 errors, freezing before either pass completed), which
retroactively makes most of the other bugs chased along the way (a
touchpad hard-lock, an `i915` GPU driver crash, kernel heap corruption)
suspect as RAM-corruption symptoms rather than confirmed independent
bugs. See `README.md`'s full saga for the diagnostic chain — it's real
and worth keeping even though the root cause turned out to be hardware.

**A second unit is inbound.** Once it has SSH access, the priorities are:
1. Harden the default credentials immediately (see
   `scripts/harden-default-credentials.sh`) — skipped on unit 1 before the
   RAM finding took priority.
2. Run `memtest86+` (see `scripts/install-memtest86-grub-entry.sh`) early
   — before chasing any driver-level theory for a crash/freeze symptom,
   not after. That ordering cost significant time on unit 1.
3. Re-verify whether the touchpad freeze and `i915` page-flip crash
   (README sections 4-5) are real, independent bugs on confirmed-good RAM,
   or don't reproduce at all once RAM isn't a confound.
4. Append a new dated section to `README.md` for unit 2 rather than
   editing/removing unit 1's writeup — the diagnostic reasoning there
   (and the "ruled out in order" discipline) is still valuable even though
   the underlying hardware died.

## Sibling repo — read before assuming anything transfers

[`GooseThings/samsung-chromebook-2-linux`](https://github.com/GooseThings/samsung-chromebook-2-linux)
covers a different Chromebook (Samsung Chromebook 2, XE503C32, **ARM**
Exynos5800, U-Boot-based firmware — not coreboot). Most of that repo is
**hardware-specific and does not apply here**:

- The entire ArchLinuxARM/U-Boot vboot signing saga (sections 1–2) — an
  ARM/U-Boot firmware limitation. This device uses coreboot+depthcharge,
  a completely different (and much more standard) boot chain.
- The `velvet-os/imagebuilder` pre-built image — targets the ARM Snow/Pit/Pi
  family specifically. Not relevant to an Intel board; use a normal x86
  Debian (or other distro) installer instead.
- Device-tree mismatch (section 5) — x86 doesn't use device trees.
- Mali/Panfrost GPU devfreq flicker fix (section 6) — Intel graphics use a
  completely different driver (`i915`). Don't assume this bug exists here;
  diagnose fresh if a similar symptom shows up.
- MAX98091 audio DAC routing fix (section 8) — codec-specific; this board
  almost certainly has different audio hardware.
- Function-row keyboard remap (section 9) — same general technique may
  apply (ChromeOS action keys reporting as plain F-keys), but the actual
  scancodes/modalias will differ and need to be recaptured for this
  keyboard.

**What does transfer** (methodology and finished tooling, not repo-specific
values): the Cinnamon desktop-environment switch process, the
TLP/schedutil/swappiness power-tuning approach, the credential-hardening
habit (change default creds immediately), the general diagnostic technique
of ruling out hypotheses in order and citing the actual command output, and
the writing style below.

## Decided so far

- **Firmware approach: flash MrChromebox firmware** (`mrchromebox.tech`),
  not the Ctrl+L legacy-boot-every-time route. Chosen for a normal
  permanent boot experience over convenience-without-case-opening.
  Write-protect screw location for this exact model revision was **not**
  confirmed from memory — verify against MrChromebox's own per-device page
  or a teardown guide before opening the case.
- Desktop environment: **Cinnamon** (matches the Peach Pi machine, same
  user preference — XFCE/LXQt/GNOME were all tried and rejected there).
- Once booted: apply the same category of post-install work as the sibling
  repo (power tuning, default-credential hardening) — but re-derive the
  actual values/commands for this hardware rather than copying blind.

## Writing style — match the sibling repo

- Narrative "saga" format: numbered `###` sections in `README.md`, each
  describing a symptom, what was ruled out and how (cite actual commands/
  output), and the actual fix.
- Cross-reference reusable scripts from prose: `` See [`scripts/foo.sh`](scripts/foo.sh). ``
- End of README: a "Diagnostics cheat sheet" of generically useful commands,
  and a "Repo contents" bullet list describing every file in `scripts/`.
- Scripts are POSIX `sh`, idempotent where reasonable, with a comment block
  at the top explaining *why*, not just what.
- Never commit real credentials/passwords/keys — this repo is public.
  Scripts that set a password should prompt interactively
  (see the sibling repo's `harden-default-credentials.sh` for the pattern).

## Workflow note

Prior work on the sibling Chromebook was done by SSHing into the live
device from a Claude Code session and driving changes directly, then
writing them up here afterward. Expect the same pattern once this device
has SSH access — check whether the user has already provided an IP/
hostname and credentials before assuming the device is unreachable.
