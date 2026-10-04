#!/bin/bash
# Number of established TCP connections to non-loopback peers, matching the
# rows shown by conky_net_peers.sh.
set -u
DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
"$DIR/conky_net_peer_hosts.sh" | awk 'END { print NR + 0 }'
