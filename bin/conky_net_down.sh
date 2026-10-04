#!/bin/bash
# Download throughput for the graph (raw bytes/second). See conky_net_rate.sh.
# A separate no-argument wrapper keeps ${execgraph} free of command arguments,
# which conky parses ambiguously.
set -u
DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
exec "$DIR/conky_net_rate.sh" rx graph
