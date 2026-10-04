#!/bin/bash
# Long-lived sampler for the Conky panels.
#
# conky otherwise forks a shell for every ${execpi}/${execi} on every refresh,
# which is where the CPU churn comes from. This loop runs the expensive probes
# (process table, CPU grid) once every SAMPLE seconds and writes their rendered
# output to state files. The panel helpers read those files, so conky itself
# only does a `cat` per refresh.
#
# Run it as a user service (see conky-sampler.service) or under the conky
# start script. It exits cleanly on SIGTERM and removes its state files.
set -u

STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}"
DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
SAMPLE="${CONKY_SAMPLE_INTERVAL:-2}"

cleanup() {
    rm -f "$STATE_DIR"/conky_sampler_*.state
    exit 0
}
trap cleanup TERM INT

while :; do
    "$DIR/conky_top_procs.sh" >"$STATE_DIR/conky_sampler_procs.state" 2>/dev/null
    "$DIR/conky_cpu_cores.sh" >"$STATE_DIR/conky_sampler_cores.state" 2>/dev/null
    sleep "$SAMPLE"
done
