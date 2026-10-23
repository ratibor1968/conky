#!/bin/bash
# GPU core utilisation in percent (no unit). Reads the shared GPU sampler (one
# query/cache covers every GPU field), falling back to AMD radeontop, else N/A.
set -u
DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

v=$("$DIR/conky_gpu_sample.sh" usage)
if [ -n "$v" ] && [ "$v" != "N/A" ]; then
    echo "$v"
    exit 0
fi

if command -v radeontop >/dev/null 2>&1; then
    val=$(radeontop -d - -l 1 2>/dev/null | grep -oP 'gpu \K[0-9.]+' | head -n1)
    if [ -n "$val" ]; then
        awk -v v="$val" 'BEGIN{printf "%.0f\n", v}'
        exit 0
    fi
fi

echo "N/A"
