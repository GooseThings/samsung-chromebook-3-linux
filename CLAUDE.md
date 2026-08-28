# Project context for Claude

This repo documents getting Linux running well on a **Samsung Chromebook 3
(XE500C13)** — Intel Celeron N3060 (Braswell), coreboot + depthcharge
firmware. As of repo creation, **the device hasn't arrived yet** — this repo
starts as prep notes/plan, to be filled in with the real diagnostic saga
once hardware is in hand.

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
