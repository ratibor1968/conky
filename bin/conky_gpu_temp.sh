#!/bin/bash
# GPU temperature in degrees C (number only, e.g. "42.0"). Reads the shared
# GPU sampler, then tries the amdgpu hwmon sensor directly, then `sensors`.
# The caller adds the "°C" suffix, so never print it here.
set -u
DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

v=$("$DIR/conky_gpu_sample.sh" temp)
if [ -n "$v" ] && [ "$v" != "N/A" ]; then
    echo "$v"
    exit 0
fi

# AMD amdgpu exposes temp1_input in millidegrees.
for h in /sys/class/hwmon/hwmon*; do
    [ "$(cat "$h/name" 2>/dev/null)" = "amdgpu" ] || continue
    if [ -r "$h/temp1_input" ]; then
        awk -v v="$(cat "$h/temp1_input")" 'BEGIN{printf "%.1f\n", v/1000}'
        exit 0
    fi
done

# Last resort: `sensors`, stripping the sign and unit.
if command -v sensors >/dev/null 2>&1; then
    val=$(sensors 2>/dev/null | awk '
        /amdgpu/      {in_gpu=1}
        in_gpu && /edge:/     {print $2; exit}
        in_gpu && /junction:/ {print $2; exit}
        /temp1:/      {print $2; exit}
    ')
    if [ -n "$val" ]; then
        val=${val#+}
        val=${val%°C}
        val=${val%C}
        printf '%s\n' "$val"
        exit 0
    fi
fi

echo "N/A"
