#!/bin/sh
# This unit was left with a short, weak default account password, same
# lesson as the sibling repo's script of the same name - change it before
# putting the device on any network you don't fully trust, ideally right
# after first boot's network setup completes.
#
# Prompts interactively rather than taking the password as an argument or
# env var, so it never ends up in shell history or process listings.
#
# Never got applied on the first XE500C13 unit before the RAM failure
# (see README section 8) took priority - do this early on the next one.

set -e

TARGET_USER="${1:-trina}"

printf 'New password for user %s: ' "$TARGET_USER"
stty -echo
read -r NEWPASS
stty echo
echo

printf '%s:%s\n' "$TARGET_USER" "$NEWPASS" | sudo chpasswd
echo "Password changed for $TARGET_USER. Verify with a fresh SSH"
echo "connection (or new sudo prompt) before closing this session, in"
echo "case something above silently failed."
