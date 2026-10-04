#!/bin/bash
# Total bytes received/transmitted on the active interface since it came up,
# formatted with decimal (SI) units. Usage: conky_net_total.sh <rx|tx>
#
# Uses the same live interface detection as the rest of the panel, so the
# totals follow a wired <-> Wi-Fi switch (and reset when the link changes,
# because the counters are per interface).
set -u

MODE="${1:-rx}"
case "$MODE" in rx | tx) ;; *) MODE=rx ;; esac

DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
IFACE=$("$DIR/conky_net_iface.sh")
[ -n "$IFACE" ] || IFACE=wlan0

case "$MODE" in
    rx) STAT="rx_bytes" ;;
    tx) STAT="tx_bytes" ;;
esac
V=$(cat "/sys/class/net/$IFACE/statistics/$STAT" 2>/dev/null || printf '0')

awk -v v="$V" 'BEGIN {
    split("B KB MB GB TB", u, " "); i = 1
    while (v >= 1000 && i < 5) { v /= 1000; i++ }
    if (i == 1) printf "%.0f %s\n", v, u[i]
    else        printf "%.1f %s\n", v, u[i]
}'
