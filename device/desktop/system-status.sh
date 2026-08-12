#!/bin/sh
set -eu

state_file=${CDMX_STATUS_STATE:-/run/cdmx-desktop/cpu-sample}
read -r total idle <<EOF
$(awk '/^cpu / {print $2+$3+$4+$5+$6+$7+$8, $5+$6}' /proc/stat)
EOF

cpu=0
if [ -r "$state_file" ]; then
    read -r previous_total previous_idle < "$state_file" || true
    elapsed=$((total - ${previous_total:-total}))
    idle_elapsed=$((idle - ${previous_idle:-idle}))
    if [ "$elapsed" -gt 0 ]; then
        cpu=$(awk -v t="$elapsed" -v i="$idle_elapsed" \
            'BEGIN {printf "%.0f", 100*(t-i)/t}')
    fi
fi
printf '%s %s\n' "$total" "$idle" > "$state_file"

memory=$(awk '/MemTotal/ {t=$2} /MemAvailable/ {a=$2} END {if (t > 0) printf "%.0f", 100*(t-a)/t; else print 0}' /proc/meminfo)
temperature=
if [ -r /sys/class/thermal/thermal_zone0/temp ]; then
    temperature=$(awk '{printf " · %.0f°C", $1/1000}' /sys/class/thermal/thermal_zone0/temp)
fi

printf '%s · CPU %s%% · RAM %s%%%s\n' "$(hostname)" "$cpu" "$memory" "$temperature"
