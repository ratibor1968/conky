#!/bin/bash
# GPU temperature in degrees C (no unit). NVIDIA first, then AMD, else N/A.
if command -v nvidia-smi >/dev/null 2>&1; then
    out=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -n1)
    if [ -n "$out" ]; then
        echo "$out"
        exit 0
    fi
fi

if command -v sensors >/dev/null 2>&1; then
    # AMD amdgpu exposes "edge" / "junction"; NVIDIA hwmon exposes "temp1"
    val=$(sensors 2>/dev/null | awk '
        /amdgpu/      {in_gpu=1}
        in_gpu && /edge:/     {print $2; exit}
        in_gpu && /junction:/ {print $2; exit}
        /temp1:/      {print $2; exit}
    ')
    if [ -n "$val" ]; then
        printf '%s\n' "${val#+}"
        exit 0
    fi
fi

echo "N/A"
