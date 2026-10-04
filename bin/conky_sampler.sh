#!/bin/bash
# Long-lived sampler for the Conky panels.
#
# conky otherwise forks a shell for every ${execpi}/${execi} on every refresh,
# which is where the CPU churn comes from. This loop runs the expensive probes
# (process table, CPU grid) once every SAMPLE seconds and writes their rendered
# output to state files. The panel helpers read those files, so conky itself
# only does a `cat` per refresh.
#
# Each state file is written to a temporary file and renamed into place, so a
# reader can never see a truncated/half-written file (which made the sections
# blink out for a frame).
#
# Run it as a user service (see conky-sampler.service) or under the conky
# start script. It exits cleanly on SIGTERM and removes its state files.
set -u

STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}"
DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
SAMPLE="${CONKY_SAMPLE_INTERVAL:-2}"

cleanup() {
    rm -f "$STATE_DIR"/conky_sampler_*.state "$STATE_DIR"/conky_sampler_*.tmp.*
    exit 0
}
trap cleanup TERM INT

# $1 = output name, rest = command. Writes atomically so readers never see a
# partial file.
emit() {
    local name="$1"; shift
    local tmp="$STATE_DIR/conky_sampler_${name}.tmp.$$"
    if "$@" >"$tmp" 2>/dev/null; then
        mv -f "$tmp" "$STATE_DIR/conky_sampler_${name}.state"
    else
        rm -f "$tmp"
    fi
}

while :; do
    emit procs "$DIR/conky_top_procs.sh"
    emit cores "$DIR/conky_cpu_cores.sh"
    sleep "$SAMPLE"
done
