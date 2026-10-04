#!/bin/bash
# Upload throughput for the graph (raw bytes/second). See conky_net_rate.sh.
#
# conky's built-in ${upspeedgraph} keeps a single global high-water mark shared
# by every speed graph and resets it to ~0 for one frame when the peak scrolls
# out of the buffer, which makes a bursty trace flash and re-scale. Plotting our
# own counter sample with a plain ${execgraph} (auto scale, no shared state)
# avoids that; this wrapper exists purely because ${execgraph} should not need
# command-line arguments.
set -u
DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
exec "$DIR/conky_net_rate.sh" tx graph
