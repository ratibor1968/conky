#!/bin/bash
# GPU power draw in watts (e.g. "21 W"). NVIDIA first, then AMD, else N/A.
if command -v nvidia-smi >/dev/null 2>&1; then
    out=$(nvidia-smi --query-gpu=power.draw --format=csv,noheader,nounits 2>/dev/null | head -n1)
    if [ -n "$out" ]; then
        awk -v v="$out" 'BEGIN{printf "%.0f W\n", v}'
        exit 0
    fi
fi

# AMD amdgpu exposes power1_input in microwatts
for h in /sys/class/hwmon/hwmon*; do
    [ "$(cat "$h/name" 2>/dev/null)" = "amdgpu" ] || continue
    if [ -r "$h/power1_input" ]; then
        awk -v v="$(cat "$h/power1_input")" 'BEGIN{printf "%.0f W\n", v/1e6}'
        exit 0
    fi
done

echo "N/A"
