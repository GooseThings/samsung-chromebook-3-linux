#!/bin/sh
# Continuously samples system resource state to a CSV log, for
# correlating with the i915 display-corruption bug (README section 15)
# after the fact -- every recurrence so far has coincided with low free
# memory, but that was only ever checked in hindsight via one-off
# snapshots. This keeps a running history instead.
#
# Rotates to a new file each day and deletes anything older than 7 days,
# since this board's eMMC storage is small. Run continuously via the
# systemd service installed by install-resource-monitor.sh, not by hand.

LOGDIR="/var/log/resource-monitor"
INTERVAL="${1:-5}"

mkdir -p "$LOGDIR"

while true; do
  find "$LOGDIR" -name "resources-*.csv" -mtime +7 -delete 2>/dev/null

  today=$(date +%Y-%m-%d)
  logfile="$LOGDIR/resources-$today.csv"
  if [ ! -f "$logfile" ]; then
    echo "timestamp,load1,load5,load15,mem_total_kb,mem_free_kb,mem_available_kb,swap_used_kb,zswap_stored_pages,zswap_pool_pct,cpu0_freq_khz,cpu_temp_millic,top_mem_proc,top_mem_pct" > "$logfile"
  fi

  ts=$(date -Iseconds)
  read -r load1 load5 load15 _ < /proc/loadavg

  mem_total=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
  mem_free=$(awk '/^MemFree:/{print $2}' /proc/meminfo)
  mem_avail=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
  swap_total=$(awk '/^SwapTotal:/{print $2}' /proc/meminfo)
  swap_free=$(awk '/^SwapFree:/{print $2}' /proc/meminfo)
  swap_used=$((swap_total - swap_free))

  zswap_pages=$(cat /sys/kernel/debug/zswap/stored_pages 2>/dev/null || echo 0)
  zswap_pool=$(cat /sys/module/zswap/parameters/max_pool_percent 2>/dev/null || echo 0)

  cpu_freq=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null || echo 0)
  cpu_temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo 0)

  top_line=$(ps -eo comm,%mem --sort=-%mem --no-headers | head -1)
  top_proc=$(echo "$top_line" | awk '{print $1}')
  top_pct=$(echo "$top_line" | awk '{print $2}')

  echo "$ts,$load1,$load5,$load15,$mem_total,$mem_free,$mem_avail,$swap_used,$zswap_pages,$zswap_pool,$cpu_freq,$cpu_temp,$top_proc,$top_pct" >> "$logfile"

  sleep "$INTERVAL"
done
