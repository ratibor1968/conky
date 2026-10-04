#!/bin/bash
# Print the remote host of every established TCP connection, one per line, with
# loopback/wildcard entries removed. IPv4 and IPv6 (with or without brackets)
# are normalised to a bare address.
#
# This is the single parsing point for the connection side. Unlike the original
# `$NF` approach it uses `ss -H` (no header) and takes the peer field (4)
# explicitly, so the layout is stable whether or not extra columns are present.
set -u

ss -Htn state established 2>/dev/null | awk '{
    host = $4
    if (host ~ /^\[/) { sub(/\]:[0-9]*$/, "", host) }
    else { sub(/:[0-9]*$/, "", host) }
    gsub(/^\[|\]$/, "", host)
    sub(/^::ffff:/, "", host)
    if (host == "" || host == "*" || host == "0.0.0.0") next
    if (host == "::1" || host ~ /^127\./) next
    print host
}'
