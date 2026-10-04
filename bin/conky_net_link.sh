#!/bin/bash
# Emits the LINK block of the network panel as conky markup, consumed with
# ${execpi}. The active interface is detected at call time, so the panel
# follows a wired <-> Wi-Fi switch with no restart.
set -u

DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
IFACE=$("$DIR/conky_net_iface.sh")
[ -n "$IFACE" ] || IFACE=wlan0

case "$IFACE" in
    wl*) TYPE="Wi-Fi" ;;
    en* | eth*) TYPE="Ethernet" ;;
    ww* | rmnet*) TYPE="Cellular" ;;
    tun* | tap* | wg* | ppp*) TYPE="VPN" ;;
    *) TYPE="Link" ;;
esac

ADDR=$(ip -4 -o addr show dev "$IFACE" 2>/dev/null | awk '{ print $4 }' | cut -d/ -f1 | head -n1)
[ -n "$ADDR" ] || ADDR="N/A"

GW=$(ip route show default 2>/dev/null |
    awk '{ for (i = 1; i <= NF; i++) if ($i == "via") { print $(i + 1); exit } }')
[ -n "$GW" ] || GW="N/A"

printf '${color2}Interface${alignr}${color3}%s (%s)\n' "$IFACE" "$TYPE"

if [ "$TYPE" = "Wi-Fi" ]; then
    # nmcli gives the SSID and signal as a percentage. Fall back to `iw`
    # (SSID only) when NetworkManager is unavailable.
    line=$(nmcli -t -f ACTIVE,SSID,SIGNAL dev wifi 2>/dev/null | grep '^yes:' | head -n1)
    ssid=""
    signal=""
    if [ -n "$line" ]; then
        v="${line#yes:}"
        signal="${v##*:}"
        ssid="${v%:*}"
        ssid="${ssid//\\:/:}" # unescape colons in the SSID
    else
        ssid=$(iw dev "$IFACE" link 2>/dev/null | awk -F': ' '/SSID:/{ print $2; exit }')
    fi

    if [ -n "$ssid" ]; then
        if [ -n "$signal" ]; then
            if [ "$signal" -ge 70 ] 2>/dev/null; then sc=6
            elif [ "$signal" -ge 40 ] 2>/dev/null; then sc=4
            else sc=5; fi
            printf '${color2}SSID${alignr}${color3}%s  ${color%s}%s%%${color}\n' "$ssid" "$sc" "$signal"
        else
            printf '${color2}SSID${alignr}${color3}%s${color}\n' "$ssid"
        fi
    fi
fi

printf '${color2}Address${alignr}${color3}%s${color}\n' "$ADDR"
printf '${color2}Gateway${alignr}${color3}%s${color}\n' "$GW"
