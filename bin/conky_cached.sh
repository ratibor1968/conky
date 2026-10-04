#!/bin/bash
# Read a value precomputed by conky_sampler.sh, falling back to running the
# real helper if the sampler is not running or its state is stale.
#
# Usage: conky_cached.sh <name> <max_age_seconds> <fallback-command...>
#   <name> is the key conky_sampler_<name>.state
set -u

name="${1:-}"; shift || true
age="${1:-0}"; shift || true
[ -n "$name" ] && [ $# -gt 0 ] || { echo "usage: conky_cached.sh <name> <age> <command...>" >&2; exit 2; }

STATE="${XDG_RUNTIME_DIR:-/tmp}/conky_sampler_${name}.state"

if [ -r "$STATE" ]; then
    now=$(date +%s)
    mtime=$(stat -c %Y "$STATE" 2>/dev/null || echo 0)
    if [ "$mtime" -gt 0 ] && [ $((now - mtime)) -le "$age" ]; then
        cat "$STATE"
        exit 0
    fi
fi

exec "$@"
