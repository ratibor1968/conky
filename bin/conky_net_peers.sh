#!/bin/bash
# Established TCP peers, grouped by reverse-DNS hostname and ranked by
# connection count. Emits a header plus conky markup (consumed with ${execpi}).
#
# Reverse lookups are slow and can block, so they go through a small on-disk
# cache and only a few uncached hosts are resolved per run (each under a short
# timeout). Hosts that are still unresolved fall back to their IP, so the panel
# never stalls and names converge over a few refreshes.
set -u

LIMIT=20     # rows to display (conky has vertical room for this many)
TTL=3600     # reuse a cached name for one hour
BUDGET=4     # at most this many new lookups per run
DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
CACHE="${XDG_RUNTIME_DIR:-/tmp}/conky_net_dns.cache"
NOW=$(date +%s)

# Reduce a reverse-DNS name to its registrable domain ("host.sub.example.co.uk"
# -> "example.co.uk") so the list reads as a provider, not a random host. Names
# that are not a domain (i.e. a bare IP) are returned unchanged.
registrable() { # $1 = hostname or IP
    local n="$1"
    case "$n" in
        *[a-zA-Z]*) : ;;   # has letters -> looks like a name
        *) printf '%s' "$n"; return 0 ;;   # bare IP, leave as-is
    esac
    local n="${n%.}"        # drop trailing dot
    local IFS='.'
    local -a lab=($n)
    local k=${#lab[@]}
    [ "$k" -le 2 ] && { printf '%s' "$n"; return 0; }
    # Two-label public suffixes we care about; else assume a single-label TLD.
    case "${lab[k-2]}.${lab[k-1]}" in
        co.uk|org.uk|ac.uk|gov.uk|com.au|net.au|org.au|co.jp|co.nz|com.br|com.cn)
            printf '%s.%s.%s' "${lab[k-3]}" "${lab[k-2]}" "${lab[k-1]}" ;;
        *)
            printf '%s.%s' "${lab[k-2]}" "${lab[k-1]}" ;;
    esac
}

unset IFS

# Load the cache: IP -> name, with the time it was resolved.
declare -A NAME=() TS=()
if [ -r "$CACHE" ]; then
    while IFS=$'\t' read -r ip nm ts; do
        [ -n "${ip:-}" ] || continue
        NAME["$ip"]="$nm"
        TS["$ip"]="${ts:-0}"
    done <"$CACHE"
fi

# Group raw peers by address first (cheap), then resolve names.
mapfile -t rows < <("$DIR/conky_net_peer_hosts.sh" | sort | uniq -c | sort -rn)

declare -A SUM=() # resolved name -> connection count
disp=()           # first-seen order of resolved names
budget=$BUDGET

for row in "${rows[@]}"; do
    [ -n "$row" ] || continue
    read -r cnt ip <<<"$row"
    [ -n "${ip:-}" ] || continue

    if [ -n "${NAME[$ip]:-}" ] && [ $((NOW - ${TS[$ip]:-0})) -lt "$TTL" ]; then
        nm="${NAME[$ip]}"
    elif [ "$budget" -gt 0 ]; then
        # Prefer a reverse-DNS PTR; fall back to the operator (ASN org) so an
        # address without PTR still reads as a name instead of a raw IP. The
        # ASN org merges an operator's v4 and v6 peers into one row, which is
        # the "prefer IPv4" behaviour (no separate IPv6 entry for the same net).
        nm=$(timeout 0.5 getent hosts "$ip" 2>/dev/null | awk '{ print $2; exit }')
        [ -n "$nm" ] || nm=$(timeout 0.5 dig +short -x "$ip" 2>/dev/null | sed 's/\.$//' | head -n1)
        if [ -z "$nm" ]; then
            nm=$("$DIR/conky_net_asn.sh" "$ip")
            case "$nm" in
                "" | N/A | "$ip") nm="$ip" ;;   # no operator name: keep the IP
            esac
        fi
        NAME["$ip"]="$nm"
        TS["$ip"]="$NOW"
        budget=$((budget - 1))
    else
        nm="${NAME[$ip]:-$ip}" # stale name, or the raw IP until we get budget
    fi

    # Group by the registrable domain (falls back to the raw IP with no PTR).
    nm=$(registrable "$nm")
    if [ -z "${SUM[$nm]:-}" ]; then
        disp+=("$nm")
        SUM["$nm"]=0
    fi
    SUM["$nm"]=$((SUM["$nm"] + cnt))
done

HOSTW=28   # visible hostname width; longer names get "..."
printf '${color7}%-*s${alignr}CONNS${color}\n' "$HOSTW" "HOST"
n=0
for nm in "${disp[@]}"; do
    [ "$n" -lt "$LIMIT" ] || break
    if [ "${#nm}" -gt "$HOSTW" ]; then disp2="${nm:0:$((HOSTW - 3))}..."; else disp2="$nm"; fi
    printf '${color2}%-*s${alignr}${color3}%s${color}\n' "$HOSTW" "$disp2" "${SUM[$nm]}"
    n=$((n + 1))
done

# Persist the cache, dropping entries unused for a week so it cannot grow
# without bound.
tmp="${CACHE}.$$"
if : >"$tmp" 2>/dev/null; then
    for ip in "${!NAME[@]}"; do
        [ $((NOW - ${TS[$ip]:-0})) -lt 604800 ] || continue
        printf '%s\t%s\t%s\n' "$ip" "${NAME[$ip]}" "${TS[$ip]}" >>"$tmp"
    done
    mv -f "$tmp" "$CACHE" 2>/dev/null
fi
