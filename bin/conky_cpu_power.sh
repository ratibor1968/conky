#!/bin/bash
# CPU package power draw in watts (e.g. "65 W") from RAPL energy counters.
# The counter is world-readable on this system, so no root is needed.
# Watts are derived from the delta since the previous call, using a small
# state file instead of sleeping (so conky never blocks). Prints "N/A"
# until there have been two samples or if RAPL is unavailable.
set -u

RAWL="/sys/class/powercap/intel-rapl:0/energy_uj"
MAXL="${RAWL%/*}/max_energy_range_uj"
STATE="${XDG_RUNTIME_DIR:-/tmp}/conky_cpu_power.state"

[ -r "$RAWL" ] || { echo "N/A"; exit 0; }

now=$(date +%s%N)
e=$(cat "$RAWL" 2>/dev/null) || { echo "N/A"; exit 0; }
out="N/A"

if [ -r "$STATE" ]; then
    read -r pe pt < "$STATE" 2>/dev/null || true
    if [ -n "${pe:-}" ] && [ -n "${pt:-}" ]; then
        dt_ms=$(( (now - pt) / 1000000 ))
        de=$(( e - pe ))
        if [ "$de" -lt 0 ]; then                       # counter wrapped
            mx=$(cat "$MAXL" 2>/dev/null || echo 0)
            de=$(( de + mx ))
        fi
        if [ "$dt_ms" -gt 0 ] && [ "$de" -ge 0 ]; then
            out=$(awk -v de="$de" -v dt="$dt_ms" \
                'BEGIN{printf "%.0f W", (de/1e6)/(dt/1000)}')
        fi
    fi
fi

printf '%s %s\n' "$e" "$now" > "$STATE" 2>/dev/null
printf '%s\n' "$out"
