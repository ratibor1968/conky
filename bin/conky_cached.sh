#!/bin/bash
# Read a value precomputed by conky_sampler.sh, falling back to running the
# real helper only when the sampler is not running.
#
# Usage: conky_cached.sh <name> <fallback-command...>
#   <name> is the key conky_sampler_<name>.state
#
# The state file is written atomically by the sampler (rename), so a plain
# `cat` here never returns a partial value. While the sampler is alive we
# always trust its file (even if a tick is late); the fallback exists only for
# when the sampler is not running at all.
set -u

name="${1:-}"; shift || true
[ -n "$name" ] && [ $# -gt 0 ] || { echo "usage: conky_cached.sh <name> <command...>" >&2; exit 2; }

STATE="${XDG_RUNTIME_DIR:-/tmp}/conky_sampler_${name}.state"

sampler_alive() {
    pgrep -f 'bin/conky_sampler\.sh' >/dev/null 2>&1
}

if [ -r "$STATE" ]; then
    if sampler_alive; then
        cat "$STATE"
        exit 0
    fi
    # Sampler gone: use the file if it is still recent, else recompute.
    now=$(date +%s)
    mtime=$(stat -c %Y "$STATE" 2>/dev/null || echo 0)
    if [ "$mtime" -gt 0 ] && [ $((now - mtime)) -le 10 ]; then
        cat "$STATE"
        exit 0
    fi
fi

# No usable state: compute on demand (and opportunistically start the sampler).
if ! sampler_alive; then
    DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
    setsid "$DIR/conky_sampler.sh" >/dev/null 2>&1 &
fi
exec "$@"
