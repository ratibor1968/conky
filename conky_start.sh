#!/usr/bin/env bash
# Start the Conky panels (system + network). Safe to run repeatedly.
#
# The network panel detects the active interface at runtime (see
# bin/conky_net_iface.sh), so there is nothing to render per login and a
# wired <-> Wi-Fi switch is followed live. Set CONKY_IFACE to pin an interface;
# it is exported to the panels.
set -u

DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
BIN="$DIR/bin"
RUN="$DIR/run"

if ! command -v conky >/dev/null 2>&1; then
    echo "conky is not installed. Run: sudo pacman -S conky otf-font-awesome" >&2
    exit 1
fi

# Make sure helpers are executable (exfat / fresh copies may lack +x).
chmod +x "$BIN"/*.sh 2>/dev/null

# Keep the long-lived sampler running so conky only has to read its state files.
# Prefer systemd --user when available; otherwise start it directly.
if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
    if [ -f "$DIR/conky-sampler.service" ]; then
        mkdir -p "$HOME/.config/systemd/user"
        cp -f "$DIR/conky-sampler.service" "$HOME/.config/systemd/user/" 2>/dev/null
        systemctl --user daemon-reload 2>/dev/null
        systemctl --user start conky-sampler.service 2>/dev/null
    fi
elif ! pgrep -f "$BIN/conky_sampler.sh" >/dev/null 2>&1; then
    setsid "$BIN/conky_sampler.sh" >/dev/null 2>&1 &
fi

# Optional interface override, consumed by bin/conky_net_iface.sh.
export CONKY_IFACE="${CONKY_IFACE:-}"

# Serialize concurrent invocations (e.g. autostart racing session restore) so
# two runs can't each spawn a pair of panels.
mkdir -p "$RUN"
exec 9>"$RUN/.conky_start.lock"
if ! flock -n 9; then
    echo "conky_start.sh: another instance is already running, exiting." >&2
    exit 0
fi

# Restart cleanly. Kill any running panels and *wait* until they are actually
# gone; a fixed sleep can race with a slow exit and leave stale instances
# behind (which KDE then saves and restores, doubling the panels each login).
if pgrep -x conky >/dev/null 2>&1; then
    pkill -x conky 2>/dev/null
    for _ in $(seq 1 50); do
        pgrep -x conky >/dev/null 2>&1 || break
        sleep 0.1
    done
    # Escalate if a process refuses to exit.
    pgrep -x conky >/dev/null 2>&1 && pkill -9 -x conky 2>/dev/null
fi

# 9>&- closes the lock fd in the children so the daemonized conky processes
# don't keep the lock held after this script exits.
conky -d -c "$DIR/conky.conf" 9>&- &
conky -d -c "$DIR/conky_network.conf" 9>&- &
