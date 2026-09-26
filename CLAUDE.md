# Project context for Claude

This repo documents getting Linux running well on a **Samsung Chromebook 3
(XE500C13)** — Intel Celeron N3060 (Braswell), MrChromebox Full ROM
(UEFI/edk2) firmware. The first unit has already arrived, been fully
diagnosed, and retired — `memtest86+` found severe soldered-RAM failure
(3000 then 8314 errors, freezing before either pass completed), which
retroactively makes most of the other bugs chased along the way (a
touchpad hard-lock, an `i915` GPU driver crash, kernel heap corruption)
suspect as RAM-corruption symptoms rather than confirmed independent
bugs. The `README.md` is now a lean problem→fix reference; the full
diagnostic saga lives in git history (through commit `62b59a9`) if the
reasoning behind any fix is ever needed.

**Unit 2 is the live machine** (hostname `chromux`, Debian 13 + Cinnamon,
user `levi`). Firmware flashed, RAM passed one `memtest86+` pass, power
tuning applied. Its write-up is the "Unit 2 — live machine" part of
`README.md`, a lean problem→fix reference (not the old numbered saga).
Add or update a problem/fix subsection there rather than editing unit 1's
part; work the diagnostic reasoning ("ruled out in order") out in the
session and commit only the conclusion and the fix, keeping red herrings
in commit messages, not the README. Refer to unit 1's material as
"Unit 1" — the numbered sections are gone, so don't cite section numbers.

Open items on unit 2 (see README "Open items (unit 2)" for detail):
1. `i915` display corruption — soak-testing the 320MHz RPS pin
   (`pin-i915-gpu-freq.service`) with only `i915.enable_psr=0` left on
   the kernel cmdline. Check the journal (`journalctl -b -k | grep -i
   i915`) for new `i915` errors — not raw `dmesg`, which is restricted
   for `levi` — before assuming any "screen went black" report is this
   bug; the memory-exhaustion hang looks the same.
2. A longer multi-pass `memtest86+` run is still outstanding.
3. `soundmodem.service` fails (unconfigured leftover from `pat`).

The screensaver crash-loop and the top-row-key gap are both resolved —
see the README. (The screensaver "PAM `account`" theory was disproven; the
PAM file was reverted to the distro default and auto-lock left off by
preference. The top-row keys now emit F1-F10 after a firmware update.)

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
  Write-protect screw location confirmed on unit 2: the only screw on
  the motherboard's underside with a printed arrow pointing at it (needs
  the board flipped) — see README "Firmware & install".
- Desktop environment: **Cinnamon** (matches the Peach Pi machine, same
  user preference — XFCE/LXQt/GNOME were all tried and rejected there).
- Once booted: apply the same category of post-install work as the sibling
  repo (power tuning, default-credential hardening) — but re-derive the
  actual values/commands for this hardware rather than copying blind.

## Writing style — match the sibling repo

- `README.md` is a lean problem→fix reference: one concise `###`
  subsection per issue (symptom in a line or two, then the fix and its
  script/doc links), not a numbered "saga". Keep red herrings and
  ruled-out steps in commit messages, not the README. (Deliberate
  divergence from the sibling repo's saga style.)
- Cross-reference reusable scripts from prose: `` See [`scripts/foo.sh`](scripts/foo.sh). ``
- End of README: a "Diagnostics cheat sheet" of generically useful commands,
  and a "Repo contents" bullet list describing every file in `scripts/`.
- Scripts are POSIX `sh`, idempotent where reasonable, with a comment block
  at the top explaining *why*, not just what.
- Never commit real credentials/passwords/keys — this repo is public.
  Scripts that set a password should prompt interactively
  (see the sibling repo's `harden-default-credentials.sh` for the pattern).

## Workflow note

Claude Code now runs **directly on the Chromebook** (unit 2) — there's no
SSH hop; commands run locally as `levi`. `levi` has sudo but not
passwordless sudo, so anything needing root has to be run by the user in
a **separate terminal window** — `! sudo ...` inside Claude Code does not
work (no TTY, so sudo can't prompt: "a terminal is required to read the
password"). For multi-step root work, write a small script to the
scratchpad and give the user one `sh <path>` line to run. `levi` is in
`adm` / `systemd-journal` (added 2026-09-26), so kernel logs and the
system journal are readable without sudo after a fresh login.

Prior work on the sibling Chromebook (and unit 2's setup before Claude
was installed on it) was done by SSHing in from a Claude Code session on
another machine, then writing it up here afterward.
