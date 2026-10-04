#!/bin/bash
# Established TCP connections grouped by the local process that owns them,
# ranked by connection count. Emits a header plus conky markup (consumed with
# ${execpi}). Complements conky_net_peers.sh (which groups by remote host).
#
# Process names come from `ss -p` ("users:(("firefox",pid=...))"). Loopback
# connections are excluded to match the host list; sockets whose owner is not
# visible (other users / kernel) are bucketed as "?".
set -u

LIMIT=10
HOSTW=28

ss -Htnp state established 2>/dev/null | awk '
{
    if ($4 ~ /^\[/) { sub(/\]:[0-9]*$/, "", $4) } else { sub(/:[0-9]*$/, "", $4) }
    host = $4
    gsub(/^\[|\]$/, "", host); sub(/^::ffff:/, "", host)
    if (host == "" || host == "*" || host == "0.0.0.0") next
    if (host == "::1" || host ~ /^127\./) next
    name = "?"
    if (match($0, /users:\(\("/)) {
        rest = substr($0, RSTART + 9)
        p = index(rest, "\"")
        if (p > 0) name = substr(rest, 1, p - 1)
    }
    cnt[name]++
}
END {
    for (k in cnt) print cnt[k], k
}' | sort -rn | head -n"$LIMIT" | {
    printf '${color7}%-*s${alignr}CONNS${color}\n' "$HOSTW" "PROCESS"
    while read -r cnt proc; do
        [ -n "$proc" ] || continue
        if [ "${#proc}" -gt "$HOSTW" ]; then d="${proc:0:$((HOSTW - 3))}..."; else d="$proc"; fi
        printf '${color2}%-*s${alignr}${color3}%s${color}\n' "$HOSTW" "$d" "$cnt"
    done
}
