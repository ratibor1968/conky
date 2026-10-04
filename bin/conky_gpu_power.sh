#!/bin/bash
# GPU power draw in watts (e.g. "21 W"). Reads the shared GPU sampler, then
# falls back to AMD, else N/A.
set -u
DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

if command -v nvidia-smi >/dev/null 2>&1; then
    v=$("$DIR/conky_gpu_sample.sh" power)
    if [ -n "$v" ] && [ "$v" != "N/A" ]; then
        awk -v v="$v" 'BEGIN{printf "%.0f W\n", v}'
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
