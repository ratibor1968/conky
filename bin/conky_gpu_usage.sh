#!/bin/bash
# GPU core utilisation in percent (no unit). NVIDIA first, then AMD, else N/A.
if command -v nvidia-smi >/dev/null 2>&1; then
    out=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -n1)
    if [ -n "$out" ]; then
        echo "$out"
        exit 0
    fi
fi

if command -v radeontop >/dev/null 2>&1; then
    radeontop -d - -l 1 2>/dev/null | grep -oP 'gpu \K[0-9]+' | head -n1
    exit 0
fi

echo "N/A"
