#!/bin/sh
# Installs system-resource-monitor.sh as a continuous systemd service,
# logging to /var/log/resource-monitor/resources-YYYY-MM-DD.csv. Written
# to help pin down the still-unresolved i915 display-corruption bug
# (README section 15) by giving it a real memory/CPU/thermal history to
# check against, instead of only whatever was checked by hand at the
# moment someone noticed the screen glitch.
#
# Run as a user with sudo.

set -e

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

sudo install -m 755 "$SCRIPT_DIR/system-resource-monitor.sh" /usr/local/sbin/system-resource-monitor.sh

sudo tee /etc/systemd/system/system-resource-monitor.service > /dev/null <<'EOF'
[Unit]
Description=Continuous system resource logger (for correlating with the i915 display bug)
After=multi-user.target

[Service]
Type=simple
ExecStart=/usr/local/sbin/system-resource-monitor.sh 5
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now system-resource-monitor.service

echo "Done. Logging every 5s to /var/log/resource-monitor/resources-YYYY-MM-DD.csv"
echo "Check status with: systemctl status system-resource-monitor.service"
echo "Tail live with:    tail -f /var/log/resource-monitor/resources-\$(date +%Y-%m-%d).csv"
