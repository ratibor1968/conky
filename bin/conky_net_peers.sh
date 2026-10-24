#!/bin/bash
# Established TCP peers, grouped by host and ranked by connection count. Emits a
# header plus conky markup (consumed with ${execpi}).
#
# Reverse lookups are slow and can block, so they go through a small on-disk
# cache and only a few uncached hosts are resolved per run (each under a short
# timeout). Hosts that are still unresolved fall back to their IP, so the panel
# never stalls and names converge over a few refreshes.
#
# Internet peers are grouped by registrable domain, one row per provider. Peers
# on a private network are never collapsed: the router names every DHCP client
# under its own domain (bitaxe1.fritz.box, Apple-TV-Wohnzimmer.fritz.box, ...),
# so collapsing them all to "fritz.box" would make LAN devices read as traffic
# to the gateway. LAN rows keep the device name plus its numeric address and are
# drawn in teal. Use --self-test to re-check these labelling rules.
set -u

LIMIT=20     # rows to display (conky has vertical room for this many)
HOSTW=28     # visible hostname width; longer names get "..."
TTL=86400    # reuse a cached name for a day (reverse names rarely change)
TTL_LAN=900  # LAN names follow DHCP leases, which do get reassigned
BUDGET=2     # at most this many new lookups per run (each may hit the network)
DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
CACHE="${CONKY_NET_DNS_CACHE:-${XDG_RUNTIME_DIR:-/tmp}/conky_net_dns.cache}"
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
    # Special-use domains (home routers, mDNS, reverse trees): every label there
    # identifies one device, so the name is kept whole instead of collapsed.
    case "${lab[k-2]}.${lab[k-1]}" in
        fritz.box | home.arpa | in-addr.arpa | ip6.arpa)
            printf '%s' "$n"; return 0 ;;
    esac
    case "${lab[k-1]}" in
        fritz | local | lan | home | internal | invalid | localhost | localdomain)
            printf '%s' "$n"; return 0 ;;
    esac
    # Two-label public suffixes we care about; else assume a single-label TLD.
    case "${lab[k-2]}.${lab[k-1]}" in
        co.uk|org.uk|ac.uk|gov.uk|com.au|net.au|org.au|co.jp|co.nz|com.br|com.cn)
            printf '%s.%s.%s' "${lab[k-3]}" "${lab[k-2]}" "${lab[k-1]}" ;;
        *)
            printf '%s.%s' "${lab[k-2]}" "${lab[k-1]}" ;;
    esac
}

# True for an address on a private or link-local network. Their reverse names all
# come from the local router, so one row has to mean one device.
is_private() { # $1 = address
    case "$1" in
        10.* | 192.168.* | 172.1[6-9].* | 172.2[0-9].* | 172.3[01].*) return 0 ;;
        127.* | 169.254.*) return 0 ;;
        ::1 | [Ff][Ee]8*:* | [Ff][Cc]*:* | [Ff][Dd]*:*) return 0 ;;
    esac
    return 1
}

# Row label for a LAN peer: the device name and its numeric address, so several
# devices under the router domain stay separate and readable ("bitaxe1.fritz.box"
# + 192.168.178.62 -> "bitaxe1@192.168.178.62"). When the full address would not
# fit the column, the last octet is used instead ("bitaxe1@.62"), the rest of the
# address being the subnet the LINK line already shows. A private IPv6 peer never
# fits, so its name alone is the row; bin/conky_net_peers_detail.sh prints the
# full addresses. With no name at all the bare address is the row.
lan_label() { # $1 = resolved name, $2 = address
    local nm="$1" ip="$2" host short keep
    if [ "$nm" = "$ip" ]; then host=''; else host="${nm%%.*}"; fi
    case "$host" in *[!A-Za-z0-9_-]*) host='' ;; esac
    if [ -z "$host" ]; then
        printf '%s' "$ip"
        return 0
    fi
    if [ $((${#host} + 1 + ${#ip})) -le "$HOSTW" ]; then
        printf '%s@%s' "$host" "$ip"
        return 0
    fi
    case "$ip" in
        *.*)
            short="${ip##*.}"
            if [ $((${#host} + 2 + ${#short})) -le "$HOSTW" ]; then
                printf '%s@.%s' "$host" "$short"
                return 0
            fi
            keep=$((HOSTW - 5 - ${#short}))
            if [ "$keep" -le 0 ]; then printf '%s' "$ip"; return 0; fi
            printf '%s...@.%s' "${host:0:$keep}" "$short"
            ;;
        *)
            if [ "${#host}" -le "$HOSTW" ]; then printf '%s' "$host"
            else printf '%s...' "${host:0:$((HOSTW - 3))}"; fi
            ;;
    esac
}

# Regression check for the labelling rules: the defect this guards against is a
# LAN name collapsing onto the router's domain, which makes a local device read
# as traffic to the gateway. Run "conky_net_peers.sh --self-test" after editing.
if [ "${1:-}" = "--self-test" ]; then
    fail=0
    check() { # $1 = case, $2 = got, $3 = expected
        [ "$2" = "$3" ] || { printf 'FAIL  %s: got "%s", want "%s"\n' "$1" "$2" "$3"; fail=1; }
    }
    priv() { is_private "$1" && printf yes || printf no; }
    check 'provider collapse'  "$(registrable 'cdn.img.example.co.uk')"               'example.co.uk'
    check 'plain TLD collapse' "$(registrable 'a1.g.twimg.com')"                      'twimg.com'
    check 'bare IP kept'       "$(registrable '203.0.113.9')"                         '203.0.113.9'
    check 'router domain kept' "$(registrable 'bitaxe1.fritz.box')"                   'bitaxe1.fritz.box'
    check 'mDNS name kept'     "$(registrable 'druckers.home.arpa')"                  'druckers.home.arpa'
    check 'lan label'          "$(lan_label 'bitaxe1.fritz.box' '192.168.178.62')"    'bitaxe1@192.168.178.62'
    check 'lan label no name'  "$(lan_label '192.168.178.62' '192.168.178.62')"       '192.168.178.62'
    check 'lan label fits'     "$(lan_label 'Apple-TV-Wohnzimmer.fritz.box' '192.168.178.123')" 'Apple-TV-Wohnzimmer@.123'
    check 'lan label v6'       "$(lan_label 'nas.fritz.box' 'fe80::36e1:a9ff:fe1f:8552')" 'nas'
    check 'private v4 .178'    "$(priv '192.168.178.62')"   'yes'
    check 'private v4 172/16'  "$(priv '172.20.5.6')"       'yes'
    check 'private v4 10/8'    "$(priv '10.0.0.5')"         'yes'
    check 'public v4'          "$(priv '13.37.0.65')"       'no'
    check 'link-local v6'      "$(priv 'fe80::36e1:a9ff:fe1f:8552')" 'yes'
    check 'ULA v6'             "$(priv 'fd03:b9a4:c532::1')" 'yes'
    check 'public v6'          "$(priv '2a04:4e42:200::223')" 'no'
    if [ "$fail" = 0 ]; then printf 'self-test: ok (16 labelling rules)\n'
    else printf 'self-test: FAILED\n'; fi
    exit "$fail"
fi

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

declare -A SUM=() # row label -> connection count
declare -A COL=() # row label -> conky colour for that row
disp=()           # first-seen order of row labels
budget=$BUDGET

# Resolve names in a separate pass so the lookup budget goes to private peers
# first: their answer comes from the router without leaving the LAN, and a local
# device is the row you most need to recognise. Public providers then take what
# is left of the budget and converge over the next few refreshes.
resolve() { # $1 = address; fills NAME/TS
    local ip="$1" nm ttl=$TTL
    is_private "$ip" && ttl=$TTL_LAN
    [ -n "${NAME[$ip]:-}" ] && [ $((NOW - ${TS[$ip]:-0})) -lt "$ttl" ] && return 0
    [ "$budget" -gt 0 ] || return 0

    # Prefer a reverse-DNS PTR; fall back to the operator (ASN org) so an address
    # without PTR still reads as a name instead of a raw IP. The ASN org merges
    # an operator's v4 and v6 peers into one row, which is the "prefer IPv4"
    # behaviour (no separate IPv6 entry for the same net).
    nm=$(timeout 0.5 getent hosts "$ip" 2>/dev/null | awk '{ print $2; exit }')
    [ -n "$nm" ] || nm=$(timeout 0.5 dig +short -x "$ip" 2>/dev/null | sed 's/\.$//' | head -n1)
    if [ -z "$nm" ]; then
        # The ASN query is only for public addresses: a private one has no ASN,
        # and the Cymru lookup would publish LAN addressing to a third-party
        # resolver for nothing.
        if is_private "$ip"; then
            nm="$ip"
        else
            nm=$("$DIR/conky_net_asn.sh" "$ip")
            case "$nm" in
                "" | N/A | "$ip") nm="$ip" ;;   # no operator name: keep the IP
            esac
        fi
    fi
    NAME["$ip"]="$nm"
    TS["$ip"]="$NOW"
    budget=$((budget - 1))
}

for want_private in 1 0; do
    for row in "${rows[@]}"; do
        [ -n "$row" ] || continue
        read -r _ ip <<<"$row"
        [ -n "${ip:-}" ] || continue
        priv=0; is_private "$ip" && priv=1
        [ "$priv" -eq "$want_private" ] && resolve "$ip"
    done
done

# Rank the rows, labelling each one. Internet peers group by registrable domain
# (or the raw address when there is no name), one row per provider. LAN peers
# keep their own device name plus address, one row per device, and are drawn in
# teal so they read as local.
for row in "${rows[@]}"; do
    [ -n "$row" ] || continue
    read -r cnt ip <<<"$row"
    [ -n "${ip:-}" ] || continue
    nm="${NAME[$ip]:-$ip}"   # stale name, or the raw IP until we get budget

    if is_private "$ip"; then
        nm=$(lan_label "$nm" "$ip")
        col='${color8}'
    else
        nm=$(registrable "$nm")
        col='${color2}'
    fi
    if [ -z "${SUM[$nm]:-}" ]; then
        disp+=("$nm")
        SUM["$nm"]=0
        COL["$nm"]="$col"
    fi
    SUM["$nm"]=$((SUM["$nm"] + cnt))
done

printf '${color7}%-*s${alignr}CONNS${color}\n' "$HOSTW" "HOST"
n=0
for nm in "${disp[@]}"; do
    [ "$n" -lt "$LIMIT" ] || break
    if [ "${#nm}" -gt "$HOSTW" ]; then disp2="${nm:0:$((HOSTW - 3))}..."; else disp2="$nm"; fi
    printf '%s%-*s${alignr}${color3}%s${color}\n' "${COL[$nm]}" "$HOSTW" "$disp2" "${SUM[$nm]}"
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
