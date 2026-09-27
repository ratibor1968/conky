#!/usr/bin/env bash
# Start the Conky panels (system + network). Safe to run repeatedly.
#
# conky_network.conf is a *template*: every @IFACE@ is replaced with the
# detected primary (default-route) network interface, and the result is
# written to ./run/conky_network.conf. Set CONKY_IFACE to override.
set -u

DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
BIN="$DIR/bin"

if ! command -v conky >/dev/null 2>&1; then
    echo "conky is not installed. Run: sudo pacman -S conky otf-font-awesome" >&2
    exit 1
fi

# Make sure helpers are executable (exfat / fresh copies may lack +x).
chmod +x "$BIN"/*.sh 2>/dev/null

# Detect the primary network interface (default route wins, so wired vs
# wireless is handled automatically).
IFACE="${CONKY_IFACE:-}"
if [ -z "$IFACE" ]; then
    IFACE=$(ip route show default 2>/dev/null |
        awk '{ for (i = 1; i <= NF; i++) if ($i == "dev") { print $(i + 1); exit } }')
fi
[ -z "$IFACE" ] && IFACE="wlan0"

# Render the network template with the detected interface.
RUN="$DIR/run"
mkdir -p "$RUN"
sed "s/@IFACE@/$IFACE/g" "$DIR/conky_network.conf" > "$RUN/conky_network.conf"

# Restart cleanly.
pkill -x conky 2>/dev/null
sleep 1

conky -d -c "$DIR/conky.conf" &
conky -d -c "$RUN/conky_network.conf" &
