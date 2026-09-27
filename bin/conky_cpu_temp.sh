#!/bin/bash
# CPU temperature in degrees C (number only, e.g. "47.8").
# Reads the CPU's own hwmon sensor *by device name* so it can never grab
# an unrelated sensor (Wi-Fi, NVMe, SPD...) the way an ordered `sensors`
# parse can:
#   AMD   -> k10temp Tctl (fallback Tccd1)
#   Intel -> coretemp "Package id 0"
# Last resort: parse `sensors`, but only within the CPU section.
set -u

# AMD k10temp
for h in /sys/class/hwmon/hwmon*; do
    [ "$(cat "$h/name" 2>/dev/null)" = "k10temp" ] || continue
    tctl=""; tccd=""
    for l in "$h"/temp*_label; do
        [ -e "$l" ] || continue
        b="${l%_label}"
        case "$(cat "$l" 2>/dev/null)" in
            Tctl)  tctl=$(cat "${b}_input" 2>/dev/null) ;;
            Tccd*) [ -n "$tccd" ] || tccd=$(cat "${b}_input" 2>/dev/null) ;;
        esac
    done
    v="${tctl:-$tccd}"
    [ -n "$v" ] && { awk -v v="$v" 'BEGIN{printf "%.1f\n", v/1000}'; exit 0; }
done

# Intel coretemp
for h in /sys/class/hwmon/hwmon*; do
    [ "$(cat "$h/name" 2>/dev/null)" = "coretemp" ] || continue
    for l in "$h"/temp*_label; do
        [ -e "$l" ] || continue
        if [ "$(cat "$l" 2>/dev/null)" = "Package id 0" ]; then
            awk -v v="$(cat "${l%_label}_input" 2>/dev/null)" \
                'BEGIN{printf "%.1f\n", v/1000}'
            exit 0
        fi
    done
done

# Fallback: `sensors`, CPU sections only
if command -v sensors >/dev/null 2>&1; then
    v=$(sensors 2>/dev/null | awk '
        /^(k10temp|coretemp|zenpower)-/ {cpu=1; next}
        cpu && /Tctl:/         {gsub(/[+°C]/, "", $2); print $2; exit}
        cpu && /Tccd1:/        {gsub(/[+°C]/, "", $2); print $2; exit}
        cpu && /Package id 0:/ {gsub(/[+°C]/, "", $4); print $4; exit}
    ')
    [ -n "$v" ] && { printf '%s\n' "$v"; exit 0; }
fi

echo "N/A"
