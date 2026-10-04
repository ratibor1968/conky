#!/bin/bash
# Throughput for the active network interface.
#
# Usage: conky_net_rate.sh <rx|tx> <text|graph>
#   text   human readable rate in decimal units, e.g. "12.3 MB/s"
#   graph  0-100 value for ${execgraph}
#
# The interface is re-detected on every call (see conky_net_iface.sh), so
# switching between wired and Wi-Fi is picked up without restarting conky.
#
# ${execgraph} only accepts values in 0-100 (larger ones are ignored with a
# warning), so the graph channel does not emit raw bytes/s: it tracks a
# slowly-decaying recent maximum and reports the current rate as a percentage
# of it. That gives a responsive trace that auto-scales without collapsing to
# zero when a burst scrolls out of the buffer.
#
# conky calls the label and the graph as two independent objects, so each
# direction *and* each format keeps its own state file. Sharing one state file
# between them would make the two interleaved samples collapse to a near-zero
# delta (each call would see the other's just-written counter).
set -u

MODE="${1:-rx}"
FORMAT="${2:-graph}"
case "$MODE" in rx | tx) ;; *) MODE=rx ;; esac
case "$FORMAT" in text | graph) ;; *) FORMAT=graph ;; esac

DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
IFACE=$("$DIR/conky_net_iface.sh")
[ -n "$IFACE" ] || IFACE=wlan0

case "$MODE" in
    rx) STAT="rx_bytes" ;;
    tx) STAT="tx_bytes" ;;
esac
COUNTER="/sys/class/net/$IFACE/statistics/$STAT"
if [ ! -r "$COUNTER" ]; then
    [ "$FORMAT" = text ] && printf '0 B/s\n' || printf '0\n'
    exit 0
fi
cur=$(cat "$COUNTER" 2>/dev/null) || cur=0

STATE="${XDG_RUNTIME_DIR:-/tmp}/conky_net_${MODE}_${FORMAT}.state"
now=$(date +%s%N)
rate=0
pmax=0
if [ -r "$STATE" ]; then
    read -r prev_iface prev pt pmax <"$STATE" 2>/dev/null || true
    if [ "${prev_iface:-}" = "$IFACE" ] && [ -n "${prev:-}" ] && [ -n "${pt:-}" ]; then
        dt=$(( (now - pt) / 1000000 )) # milliseconds
        db=$(( cur - prev ))           # bytes since the last sample
        [ "$db" -lt 0 ] && db=0        # counter wrapped / interface re-created
        if [ "$dt" -gt 0 ]; then
            rate=$(awk -v db="$db" -v dt="$dt" 'BEGIN { printf "%.0f", db / (dt / 1000) }')
        fi
    fi
fi

max=0
if [ "$FORMAT" = graph ]; then
    # Recent-maximum tracker: jump up instantly, decay ~3%/sample on the way
    # down, with a floor so a quiet link cannot amplify noise into a full bar.
    max=${pmax:-0}
    if [ "$rate" -gt "$max" ]; then
        max=$rate
    else
        max=$(( max * 97 / 100 ))
    fi
    [ "$max" -lt 1024 ] && max=1024
fi

printf '%s %s %s %s\n' "$IFACE" "$cur" "$now" "$max" >"$STATE" 2>/dev/null

if [ "$FORMAT" = text ]; then
    awk -v r="$rate" 'BEGIN {
        split("B KB MB GB TB", u, " "); i = 1
        while (r >= 1000 && i < 5) { r /= 1000; i++ }
        if (i == 1) printf "%.0f %s/s\n", r, u[i]
        else        printf "%.1f %s/s\n", r, u[i]
    }'
else
    awk -v r="$rate" -v m="$max" 'BEGIN {
        p = (m > 0) ? 100 * r / m : 0
        if (p > 100) p = 100
        if (p < 0) p = 0
        printf "%.0f\n", p
    }'
fi
