#!/bin/bash
# GPU temperature in degrees C (no unit). Reads the shared GPU sampler, then
# falls back to AMD/sensors, else N/A.
set -u
DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

if command -v nvidia-smi >/dev/null 2>&1; then
    v=$("$DIR/conky_gpu_sample.sh" temp)
    [ -n "$v" ] && [ "$v" != "N/A" ] && { echo "$v"; exit 0; }
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
