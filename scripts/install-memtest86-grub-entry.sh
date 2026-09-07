#!/bin/sh
# Installs memtest86+ and makes sure the GRUB menu actually stays visible
# long enough to select it - Debian's default GRUB_TIMEOUT (5s) plus a
# hidden-menu style makes it easy to miss the window entirely. See
# README section 8 for why this device needed it (severe RAM failure,
# found only after every driver-level theory was chased first - if a
# machine is showing scattered, unrelated-looking crashes, run this
# early rather than last).
#
# After running this, reboot and select "memtest86+ (x64)" from the GRUB
# menu. Let it run at least one full pass (0% -> 100%); any reported
# errors mean bad RAM, full stop - no kernel parameter or driver fix will
# compensate for it.

set -e

sudo apt-get install -y memtest86+

sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=15/' /etc/default/grub
sudo sed -i '/^GRUB_TIMEOUT_STYLE/d' /etc/default/grub

sudo update-grub

echo "Done. Reboot and select 'memtest86+ (x64)' from the GRUB menu."
