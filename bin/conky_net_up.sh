#!/bin/bash
# Current uplink throughput in bytes/second for the primary interface.
#
# Backs the upload graph. conky's built-in ${upspeedgraph} auto-scale keeps a
# single global high-water mark shared by *all* speed graphs, and resets it to
# ~0 for one frame when the peak scrolls out of the buffer (src/content/
# specials.cc, maxspeedval). On a bursty uplink that makes the trace flash and
# re-scale. Sampling the counter here and plotting it with a plain ${execgraph}
# (auto scale, no shared state, no collapse) avoids that.
#
# Prints 0 until two samples are available. Uses a state file, never sleeps.
set -u

IFACE=$(ip route show default 2>/dev/null |
    awk '{ for (i = 1; i <= NF; i++) if ($i == "dev") { print $(i + 1); exit } }')
[ -z "$IFACE" ] && IFACE="${CONKY_IFACE:-wlan0}"

COUNTER="/sys/class/net/$IFACE/statistics/tx_bytes"
[ -r "$COUNTER" ] || { echo 0; exit 0; }
cur=$(cat "$COUNTER" 2>/dev/null) || { echo 0; exit 0; }

STATE="${XDG_RUNTIME_DIR:-/tmp}/conky_net_up.state"
now=$(date +%s%N)
rate=0
if [ -r "$STATE" ]; then
    read -r prev_iface prev pt < "$STATE" 2>/dev/null || true
    if [ "${prev_iface:-}" = "$IFACE" ] && [ -n "${prev:-}" ] && [ -n "${pt:-}" ]; then
        dt=$(( (now - pt) / 1000000 ))   # milliseconds
        db=$(( cur - prev ))             # bytes since the last sample
        [ "$db" -lt 0 ] && db=0          # counter wrapped/reset
        if [ "$dt" -gt 0 ]; then
            rate=$(awk -v db="$db" -v dt="$dt" 'BEGIN { printf "%.0f", db / (dt / 1000) }')
        fi
    fi
fi

printf '%s %s %s\n' "$IFACE" "$cur" "$now" > "$STATE" 2>/dev/null
printf '%s\n' "$rate"
