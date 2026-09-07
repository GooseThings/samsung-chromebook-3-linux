#!/bin/sh
# The Atmel maXTouch touchpad (atmel_mxt_ts) on this board can hard-lock
# the entire machine under sustained interaction - no panic, no log line,
# the box just goes silent and unreachable. See README section 4. Root
# cause was never fully confirmed as independent of this unit's later-
# discovered failing RAM (section 8), so treat this as a safety net for
# when a USB mouse is available, not a confirmed permanent fix.
#
# Unbinds the driver live (no reboot needed) and blacklists it so it
# won't load on future boots either.
#
# Reverse with:
#   sudo rm /etc/modprobe.d/blacklist-atmel-mxt.conf
#   sudo modprobe atmel_mxt_ts

set -e

DEV="i2c-ATML0000:00"
DRIVER_DIR="/sys/bus/i2c/drivers/atmel_mxt_ts"

if [ -e "$DRIVER_DIR/$DEV" ]; then
	echo "$DEV" | sudo tee "$DRIVER_DIR/unbind" >/dev/null
	echo "Unbound $DEV live."
else
	echo "$DEV not currently bound (already unbound, or different bus path)."
fi

echo "blacklist atmel_mxt_ts" | sudo tee /etc/modprobe.d/blacklist-atmel-mxt.conf >/dev/null
echo "Blacklisted for future boots. A USB mouse will be needed until re-enabled."
