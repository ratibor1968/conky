#!/bin/bash
# Look up the network operator (ASN org) for an IPv4/IPv6 address using Team
# Cymru's DNS service -- no extra packages required. Prints a short org name
# (e.g. "Cloudflare", "Google") or the raw IP if nothing is found.
#
# Usage: conky_net_asn.sh <ip>
#
# Lookups are cached on disk with a long TTL, because an address's operator
# rarely changes and we don't want a DNS round-trip on every conky refresh.
set -u

IP="${1:-}"
[ -n "$IP" ] || { echo "N/A"; exit 0; }

DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
CACHE="${XDG_RUNTIME_DIR:-/tmp}/conky_net_asn.cache"
NOW=$(date +%s)
TTL=604800   # a week

# Cache hit?
if [ -r "$CACHE" ]; then
    hit=$(awk -F'\t' -v ip="$IP" -v now="$NOW" -v ttl="$TTL" \
        '$1==ip && (now-$3)<ttl { print $2; exit }' "$CACHE" 2>/dev/null)
    if [ -n "${hit:-}" ]; then
        printf '%s\n' "$hit"
        exit 0
    fi
fi

# Build the Cymru query name.
case "$IP" in
    *:*) # IPv6: full 32-nibble reversed form (Cymru needs all nibbles)
        q=$(python3 - "$IP" <<'PY' 2>/dev/null
import ipaddress, sys
try:
    print(ipaddress.ip_address(sys.argv[1]).reverse_pointer.replace(".ip6.arpa", ".origin6.asn.cymru.com"))
except Exception:
    pass
PY
)
        [ -n "$q" ] || q="${IP}.origin6.asn.cymru.com" ;;
    *) q="${IP}.origin.asn.cymru.com" ;;
esac

asn=$(timeout 1.5 dig +short "$q" TXT 2>/dev/null | head -n1 |
    sed 's/^"//; s/".*$//' | awk -F'|' '{ gsub(/ /,"",$1); print $1; exit }')

name="$IP"
if [ -n "$asn" ]; then
    txt=$(timeout 1.5 dig +short "AS$asn.asn.cymru.com" TXT 2>/dev/null | head -n1 |
        sed 's/^"//; s/".*$//')
    # Field 5 is like "CLOUDFLARENET - Cloudflare, Inc., US"; keep the readable
    # company name ("Cloudflare") and drop the registry code and country.
    org=$(printf '%s' "$txt" | awk -F'|' '{ print $NF; exit }')
    short=$(printf '%s' "$org" | sed 's/^ *//; s/ *$//' |
        sed 's/^[A-Z0-9-]* - //; s/,.*$//')
    if [ -n "$short" ]; then name="$short"; else name="AS$asn"; fi
fi

# Store in the cache (rewrite dropping nothing; small file).
if : >>"$CACHE" 2>/dev/null; then
    tmp="${CACHE}.$$"
    { [ -r "$CACHE" ] && grep -v -F "$IP	" "$CACHE" 2>/dev/null; printf '%s\t%s\t%s\n' "$IP" "$name" "$NOW"; } >"$tmp" 2>/dev/null &&
        mv -f "$tmp" "$CACHE" 2>/dev/null
fi

printf '%s\n' "$name"
