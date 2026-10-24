#!/bin/bash
# Disk throughput of the device backing /, formatted like the network rates.
#
# Usage: conky_disk_rate.sh <read|write> <text|graph>
#   text   human readable rate in decimal units, e.g. "12.3 MB/s"
#   graph  0-100 value for ${execgraph}
#
# The device is detected at call time (partition suffix stripped, so nvme0n1p2
# -> nvme0n1); set CONKY_DISK to override. Counters come from /proc/diskstats,
# whose fields are 512-byte sectors.
#
# ${execgraph} only accepts values in 0-100, so the graph channel tracks a
# slowly-decaying recent maximum (floored at 1 MiB/s so idle flush noise cannot
# fill the graph) and reports the current rate as a percentage of it. The decay
# is time-based, so it behaves the same at a 1 s and a 3 s refresh. Like the
# network, each direction *and* format keeps its own state file so the two
# interleaved samples cannot collapse each other's deltas.
set -u

MODE="${1:-read}"
FORMAT="${2:-graph}"
case "$MODE" in read | write) ;; *) MODE=read ;; esac
case "$FORMAT" in text | graph) ;; *) FORMAT=graph ;; esac

# Device backing /, without partition suffix (nvme0n1p2 -> nvme0n1).
DEV="${CONKY_DISK:-}"
if [ -z "$DEV" ]; then
    SRC=$(findmnt -no SOURCE / 2>/dev/null)
    DEV=$(readlink -f "$SRC" 2>/dev/null || printf '%s' "$SRC")
    DEV="${DEV#/dev/}"
    case "$DEV" in
        nvme* | mmcblk*) DEV="${DEV%p[0-9]*}" ;;
        sd* | vd* | hd*) DEV="${DEV%[0-9]*}" ;;
    esac
fi

cur=0
if [ -n "$DEV" ]; then
    cur=$(awk -v dev="$DEV" -v mode="$MODE" '$3 == dev {
        print (mode == "read") ? $6 * 512 : $10 * 512
        exit
    }' /proc/diskstats 2>/dev/null)
    [ -n "$cur" ] || cur=0
fi

STATE="${XDG_RUNTIME_DIR:-/tmp}/conky_disk_${MODE}_${FORMAT}.state"
now=$(date +%s%N)
rate=0
dt=0
pmax=0
if [ -r "$STATE" ]; then
    read -r prev_dev prev pt pmax <"$STATE" 2>/dev/null || true
    if [ "${prev_dev:-}" = "$DEV" ] && [ -n "${prev:-}" ] && [ -n "${pt:-}" ]; then
        dt=$(( (now - pt) / 1000000 )) # milliseconds
        db=$(( cur - prev ))           # bytes since the last sample
        [ "$db" -lt 0 ] && db=0        # counter wrapped / device re-created
        if [ "$dt" -gt 0 ]; then
            rate=$(awk -v db="$db" -v dt="$dt" 'BEGIN { printf "%.0f", db / (dt / 1000) }')
        fi
    fi
fi

max=0
if [ "$FORMAT" = graph ]; then
    # Recent-maximum tracker: jump up instantly, decay 3% per 3 s on the way
    # down (time-based, so the trace looks the same at any refresh cadence).
    max=${pmax:-0}
    if [ "$rate" -gt "$max" ]; then
        max=$rate
    elif [ "$dt" -gt 0 ]; then
        max=$(awk -v m="$max" -v dt="$dt" \
            'BEGIN { m *= exp(log(0.97) * dt / 3000); if (m < 0) m = 0; printf "%.0f", m }')
    fi
    [ "$max" -lt 1048576 ] && max=1048576 # floor: 1 MiB/s
fi

printf '%s %s %s %s\n' "$DEV" "$cur" "$now" "$max" >"$STATE" 2>/dev/null

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
