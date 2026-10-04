#!/bin/bash
# Print a byte count in decimal (SI) units, e.g. "60.2 GB" / "1.53 TB".
# Usage: conky_bytes.sh <memspec|swapspec|fs:used:/|fs:size:/|raw:NUMBER>
#
# conky's built-in ${mem}/${memmax}/${swap}/${fs_used}/${fs_size} always use
# binary (IEC) units (GiB, TiB). This helper formats the same values with
# decimal units (GB, TB) instead. Output is a bare number plus unit, no markup.
set -u

fmt() { # $1 = bytes
    awk -v b="$1" 'BEGIN {
        split("B KB MB GB TB PB", u, " "); i = 1
        while (b >= 1000 && i < 6) { b /= 1000; i++ }
        if (i == 1) printf "%.0f %s\n", b, u[i]
        else        printf "%.1f %s\n", b, u[i]
    }'
}

spec="${1:-}"
case "$spec" in
    mem)   fmt "$(awk '/^MemTotal:/{print $2*1024}' /proc/meminfo)" ;;
    memused) fmt "$(( $(awk '/^MemTotal:/{print $2}' /proc/meminfo) * 1024 - $(awk '/^MemAvailable:/{print $2}' /proc/meminfo) * 1024 ))" ;;
    swap)  fmt "$(awk '/^SwapTotal:/{print $2*1024}' /proc/meminfo)" ;;
    swapused) fmt "$(( ( $(awk '/^SwapTotal:/{print $2}' /proc/meminfo) - $(awk '/^SwapFree:/{print $2}' /proc/meminfo) ) * 1024 ))" ;;
    fs_used:*) fmt "$(df -B1 --output=used "${spec#fs_used:}" 2>/dev/null | tail -1)" ;;
    fs_size:*) fmt "$(df -B1 --output=size "${spec#fs_size:}" 2>/dev/null | tail -1)" ;;
    raw:*) fmt "${spec#raw:}" ;;
    *) echo "N/A" ;;
esac
