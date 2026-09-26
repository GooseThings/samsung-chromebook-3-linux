#!/bin/sh
# Installs pin-i915-gpu-freq.sh as a boot-time systemd oneshot service.
# Unproven experiment for the still-open i915 display-corruption bug
# (README section 16) -- not a confirmed fix.
#
# Run as a user with sudo.

set -e

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

sudo install -m 755 "$SCRIPT_DIR/pin-i915-gpu-freq.sh" /usr/local/sbin/pin-i915-gpu-freq.sh

sudo tee /etc/systemd/system/pin-i915-gpu-freq.service > /dev/null <<'EOF'
[Unit]
Description=Pin i915 GPU (RPS) frequency to a fixed value
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/pin-i915-gpu-freq.sh

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now pin-i915-gpu-freq.service

echo "Done. GPU frequency pinned to 320MHz, will re-apply on every boot."
echo "Check with: cat /sys/class/drm/card0/gt_min_freq_mhz /sys/class/drm/card0/gt_max_freq_mhz"
