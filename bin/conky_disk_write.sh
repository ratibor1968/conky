#!/bin/bash
# Write throughput for the disk graph. See conky_disk_rate.sh.
# A separate no-argument wrapper keeps ${execgraph} free of command arguments,
# which conky parses ambiguously.
set -u
DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
exec "$DIR/conky_disk_rate.sh" write graph
