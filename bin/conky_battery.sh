#!/bin/bash
# Battery values for the system panel.
#
# Usage: conky_battery.sh <power|status|percent>
#   power    current draw/charge in watts, e.g. "11.9 W"
#   status   Charging / Discharging / Full / ...
#   percent  charge percentage, number only
#
# Uses the first ACPI battery (normally BAT0). Set CONKY_BATTERY to override.
set -u

BAT="${CONKY_BATTERY:-}"
if [ -z "$BAT" ]; then
    for d in /sys/class/power_supply/BAT*; do
        [ -d "$d" ] || continue
        BAT="${d##*/}"
        break
    done
fi

[ -n "$BAT" ] || { echo "N/A"; exit 0; }
BASE="/sys/class/power_supply/$BAT"
[ -d "$BASE" ] || { echo "N/A"; exit 0; }

case "${1:-power}" in
    power)
        v=$(cat "$BASE/power_now" 2>/dev/null)
        if [ -z "$v" ]; then
            # Some batteries expose current_now (uA) * voltage_now (uV).
            i=$(cat "$BASE/current_now" 2>/dev/null)
            u=$(cat "$BASE/voltage_now" 2>/dev/null)
            if [ -n "$i" ] && [ -n "$u" ]; then
                v=$(awk -v i="$i" -v u="$u" 'BEGIN{printf "%.0f", i*u/1e12}')
            fi
        fi
        if [ -z "$v" ]; then
            echo "N/A"
        else
            awk -v v="$v" 'BEGIN{printf "%.1f W\n", v/1e6}'
        fi
        ;;
    status)
        cat "$BASE/status" 2>/dev/null || echo "N/A"
        ;;
    percent)
        cat "$BASE/capacity" 2>/dev/null || echo "N/A"
        ;;
    *)
        echo "N/A"
        ;;
esac
