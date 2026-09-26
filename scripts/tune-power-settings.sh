#!/bin/sh
# Battery-life tuning for the XE500C13 (Intel Celeron N3060 "Braswell",
# i915/Cherryview GPU). Adapted from the sibling Chromebook 2 repo's
# script of the same name -- CPU governor, TLP, and swappiness/zswap
# transfer as a methodology, but that repo's GPU devfreq pin does NOT:
# it worked around a Mali/Panfrost-specific flicker bug on ARM hardware
# that has no equivalent on this board's Intel i915 driver, so it's
# deliberately left out here.
#
# Run as a user with sudo.

set -e

echo "==> Installing TLP"
sudo apt-get update
sudo apt-get install -y tlp

echo "==> Setting CPU governor to schedutil (AC and battery)"
echo "    Debian's kernel already defaults to schedutil on this board, but"
echo "    pin it explicitly via TLP so nothing silently reverts it."
sudo sed -i \
  -e 's/^#\?CPU_SCALING_GOVERNOR_ON_AC=.*/CPU_SCALING_GOVERNOR_ON_AC=schedutil/' \
  -e 's/^#\?CPU_SCALING_GOVERNOR_ON_BAT=.*/CPU_SCALING_GOVERNOR_ON_BAT=schedutil/' \
  /etc/tlp.conf

sudo systemctl enable --now tlp.service
sudo tlp start

echo "==> Enabling zswap (zstd, 30% pool) and raising vm.swappiness to 100"
echo "    This board has 3.8GB RAM; zswap makes swapping to compressed RAM"
echo "    nearly free, so preferring it over page-cache eviction is a net"
echo "    win. Unit 1 tried this and reverted it, but only because it"
echo "    couldn't be disentangled from that unit's (later-confirmed) bad"
echo "    RAM -- see README section 7. Unit 2's RAM is confirmed good via"
echo "    memtest86+, so it's safe to actually evaluate this here."
if ! grep -q "zswap.enabled=1" /etc/default/grub; then
  sudo sed -i \
    's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 zswap.enabled=1 zswap.compressor=zstd zswap.max_pool_percent=30"/' \
    /etc/default/grub
  sudo update-grub
fi
echo 'vm.swappiness=100' | sudo tee /etc/sysctl.d/99-zswap-swappiness.conf
sudo sysctl -p /etc/sysctl.d/99-zswap-swappiness.conf

echo "==> Disabling the Bluetooth radio entirely (skip this block if you use it)"
sudo apt-get install -y rfkill
sudo systemctl disable --now bluetooth.service

echo "==> Installing a boot-time fixup for two settings that don't survive reboot on their own"
echo "    1) zswap.compressor=zstd on the kernel cmdline is parsed too early in boot for"
echo "       the zstd module to autoload yet, so it silently falls back to lzo -- confirmed"
echo "       by checking /sys/module/zswap/parameters/compressor after a reboot. Re-asserting"
echo "       it once userspace (and the zstd module) is up fixes it."
echo "    2) 'rfkill block bluetooth' is a live kernel-state change, not a persistent config --"
echo "       it doesn't survive a reboot on its own, and systemd-rfkill (which would normally"
echo "       persist it) is masked on this image, so it's re-applied here instead of unmasking"
echo "       a system-wide service just for this."
echo "zstd" | sudo tee /etc/modules-load.d/zswap-zstd.conf > /dev/null

sudo tee /usr/local/sbin/power-tuning-boot-fixup.sh > /dev/null <<'EOF'
#!/bin/sh
# Re-applies settings that don't survive reboot on their own.
# See scripts/tune-power-settings.sh in the repo for why.
set -e
modprobe zstd
echo zstd > /sys/module/zswap/parameters/compressor
rfkill block bluetooth
EOF
sudo chmod +x /usr/local/sbin/power-tuning-boot-fixup.sh

sudo tee /etc/systemd/system/power-tuning-boot-fixup.service > /dev/null <<'EOF'
[Unit]
Description=Re-apply zswap compressor and Bluetooth rfkill block after boot
After=systemd-modules-load.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/power-tuning-boot-fixup.sh

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now power-tuning-boot-fixup.service

echo "==> Done. Reboot required for the zswap kernel parameter and boot-fixup service to take effect."
