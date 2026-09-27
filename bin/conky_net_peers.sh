#!/bin/bash
# Established TCP peers, grouped by remote host:port, ranked by connection
# count. Emits a header plus conky markup (consumed with ${execpi}).
# NB: with "state established" ss omits the State column, so the peer
# address is the last field; $NF handles both layouts. Colons are stripped
# from the right so IPv6 literals survive.
printf '${color7}%-27.27s %s${color}\n' "PEER" "CONNS"
ss -tn state established 2>/dev/null | awk 'NR > 1 && NF >= 4 {
        peer = $NF
        port = peer
        sub(/^.*:/, "", port)
        host = peer
        sub(/:[^:]*$/, "", host)
        gsub(/^\[|\]$/, "", host)
        gsub(/^::ffff:/, "", host)
        if (host == "" || host == "*") next
        if (host == "127.0.0.1" || host == "::1") next
        print host ":" port
    }' |
    sort | uniq -c | sort -rn | head -n8 |
    awk '{ printf "${color2}%-27.27s${color3} %s${color}\n", $2, $1 }'
