#!/bin/sh
# Sets the i915 kernel command-line parameters this board actually needs,
# and removes ones that were tried and found not to help, so an ongoing
# soak test of the GPU frequency pin (README Unit 2 section 16) isn't
# muddied by leftover experiments.
#
# Kept:
#   i915.enable_psr=0 - panel self-refresh off. Reproducibly fixed the
#     Firefox+YouTube display-corruption trigger (Unit 2 section 11).
# Removed (if present):
#   i915.enable_dc=0 - display C-states off. Bug recurred with it active
#     (section 15).
#   i915.disable_power_well=0 - display power wells forced on. Never
#     touched the GT's RC6 cycling, which kept going as before (section 16).
#
# Idempotent. Run as a user with sudo; reboot afterward to apply.

set -e

GRUB=/etc/default/grub

# Strip the reverted params (with their leading space) from any GRUB_CMDLINE line.
sudo sed -i \
  -e '/^GRUB_CMDLINE_LINUX/s/ *i915\.enable_dc=[^ "]*//g' \
  -e '/^GRUB_CMDLINE_LINUX/s/ *i915\.disable_power_well=[^ "]*//g' \
  "$GRUB"

if ! grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=.*i915\.enable_psr=0' "$GRUB"; then
  sudo sed -i \
    's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 i915.enable_psr=0"/' \
    "$GRUB"
fi

grep '^GRUB_CMDLINE_LINUX_DEFAULT' "$GRUB"
sudo update-grub

echo "Done. Reboot, then confirm with: cat /proc/cmdline"
