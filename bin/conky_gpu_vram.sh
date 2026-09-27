#!/bin/bash
# GPU VRAM usage in percent (no unit). NVIDIA first, then AMD, else N/A.
if command -v nvidia-smi >/dev/null 2>&1; then
    read -r used total < <(nvidia-smi --query-gpu=memory.used,memory.total \
        --format=csv,noheader,nounits 2>/dev/null | head -n1 | tr -d ',')
    if [ -n "${used:-}" ] && [ -n "${total:-}" ] && [ "$total" -gt 0 ] 2>/dev/null; then
        awk -v u="$used" -v t="$total" 'BEGIN { printf "%.0f\n", u / t * 100 }'
        exit 0
    fi
fi

if command -v radeontop >/dev/null 2>&1; then
    radeontop -d - -l 1 2>/dev/null | grep -oP 'vram \K[0-9]+' | head -n1
    exit 0
fi

echo "N/A"
