#!/bin/bash
# Triage view of established TCP connections, one row per socket: address, remote
# port, reverse name and the local process that owns the socket. Not wired into a
# panel -- run it by hand when a CONNECTIONS row needs explaining, because the
# panel groups by host and hides ports, addresses and processes.
#
# `ss` only reports the owning process for sockets owned by this user, so rows
# for system or other-user processes show "-". Sockets with several owners list
# the first one, and the kernel truncates a process name to 15 characters.
set -u

CACHE="${CONKY_NET_DNS_CACHE:-${XDG_RUNTIME_DIR:-/tmp}/conky_net_dns.cache}"
NAMEW=24   # resolved-name column width; longer names get "..."

printf '%-4s %-25s %-5s %-*s %s\n' 'SCOPE' 'PEER' 'PORT' "$NAMEW" 'NAME (PTR/ASN)' 'PROCESS:PID'
ss -Htnp state established 2>/dev/null | awk '{
    peer = $4
    if (peer ~ /^\[/) { sub(/\]:[0-9]*$/, "", peer) } else { sub(/:[0-9]*$/, "", peer) }
    gsub(/^\[|\]$/, "", peer)
    sub(/^::ffff:/, "", peer)
    if (peer == "" || peer == "*" || peer == "0.0.0.0") next
    if (peer == "::1" || peer ~ /^127\./) next

    port = ""
    if (match($4, /:[^:]*$/)) port = substr($4, RSTART + 1)

    proc = "-"
    i = index($0, "users:((\"")
    if (i) {
        rest = substr($0, i + 9)   # "users:((" plus the quote is 9 characters
        j = index(rest, "\"")
        if (j) proc = substr(rest, 1, j - 1)
        k = index(rest, "pid=")
        if (k) { pid = substr(rest, k + 4); gsub(/[^0-9].*$/, "", pid); if (pid != "") proc = proc ":" pid }
    }
    print peer "\t" port "\t" proc
}' | sort | while IFS=$'\t' read -r peer port proc; do
    scope="wan"
    case "$peer" in
        10.* | 192.168.* | 172.1[6-9].* | 172.2[0-9].* | 172.3[01].* | 169.254.*) scope="lan" ;;
        [Ff][Ee]8*:* | [Ff][Cc]*:* | [Ff][Dd]*:*) scope="lan" ;;
    esac
    # Cached name first (no network), then a live lookup as a fallback.
    nm=$(awk -F'\t' -v ip="$peer" '$1==ip { print $2; exit }' "$CACHE" 2>/dev/null)
    [ -n "$nm" ] || nm=$(timeout 0.6 getent hosts "$peer" 2>/dev/null | awk '{ print $2; exit }')
    [ -n "$nm" ] || nm="-"
    if [ "${#nm}" -gt "$NAMEW" ]; then nm="${nm:0:$((NAMEW - 3))}..."; fi
    printf '%-4s %-25s %-5s %-*s %s\n' "$scope" "$peer" "$port" "$NAMEW" "$nm" "$proc"
done
