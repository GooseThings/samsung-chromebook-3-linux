#!/bin/sh
# Pins i915 RPS (render-engine frequency scaling) to a fixed value at
# RP1 (320MHz, the hardware efficient/guaranteed point) instead of
# letting it scale 200-600MHz dynamically -- testing whether GPU
# frequency-TRANSITIONS themselves (not the level) are contributing to
# the still-unresolved display-corruption bug, same mechanism as the
# sibling Chromebook 2 repo's GPU-devfreq flicker fix. See README
# section 16 -- this is an unproven experiment, not a confirmed fix.
echo 320 > /sys/class/drm/card0/gt_min_freq_mhz
echo 320 > /sys/class/drm/card0/gt_max_freq_mhz
