#!/bin/sh
# Change a weak/default account password, same lesson as the sibling
# repo's script of the same name - change it before putting the device on
# any network you don't fully trust, ideally right after first boot's
# network setup completes.
#
# Only relevant when the install method leaves a vendor/image default
# password behind (e.g. a pre-built image). A normal Debian netinst
# install sets real credentials interactively, so unit 2 never needed
# this - see README Unit 2 status.
#
# Prompts interactively (twice, to catch typos) rather than taking the
# password as an argument or env var, so it never ends up in shell
# history or process listings.
#
# Usage: harden-default-credentials.sh [user]   (defaults to the current user)

set -e

TARGET_USER="${1:-$(id -un)}"

if ! id "$TARGET_USER" >/dev/null 2>&1; then
	echo "No such user: $TARGET_USER" >&2
	exit 1
fi

# Always restore terminal echo, even on Ctrl+C or an error.
trap 'stty echo 2>/dev/null' EXIT
trap 'exit 130' INT TERM

stty -echo
printf 'New password for user %s: ' "$TARGET_USER"
read -r NEWPASS
echo
printf 'Repeat new password: '
read -r NEWPASS2
echo
stty echo

if [ -z "$NEWPASS" ]; then
	echo "Empty password refused." >&2
	exit 1
fi
if [ "$NEWPASS" != "$NEWPASS2" ]; then
	echo "Passwords don't match - nothing changed." >&2
	exit 1
fi

printf '%s:%s\n' "$TARGET_USER" "$NEWPASS" | sudo chpasswd
echo "Password changed for $TARGET_USER. Verify with a fresh SSH"
echo "connection (or new sudo prompt) before closing this session, in"
echo "case something above silently failed."
