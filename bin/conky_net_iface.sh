#!/bin/bash
# Print the active network interface, one line, never fails.
#
# The default-route device wins, so wired vs wireless is followed live: callers
# pick it up on every refresh instead of freezing the choice at login. If there
# is no default route (link down), fall back to the first up, non-loopback link.
#
# CONKY_IFACE overrides detection (e.g. export CONKY_IFACE=wlan0 before
# starting the panels).
set -u

if [ -n "${CONKY_IFACE:-}" ]; then
    printf '%s\n' "$CONKY_IFACE"
    exit 0
fi

IFACE=$(ip route show default 2>/dev/null |
    awk '{ for (i = 1; i <= NF; i++) if ($i == "dev") { print $(i + 1); exit } }')

if [ -z "$IFACE" ]; then
    IFACE=$(ip -o link show up 2>/dev/null |
        awk -F': ' '{ gsub(/@.*/, "", $2); if ($2 != "lo") { print $2; exit } }')
fi

printf '%s\n' "${IFACE:-wlan0}"
