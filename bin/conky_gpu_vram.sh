#!/bin/bash
# GPU VRAM usage in percent (no unit). Reads the shared GPU sampler, then AMD,
# else N/A.
set -u
DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

if command -v nvidia-smi >/dev/null 2>&1; then
    v=$("$DIR/conky_gpu_sample.sh" vram)
    [ -n "$v" ] && [ "$v" != "N/A" ] && { echo "$v"; exit 0; }
fi

if command -v radeontop >/dev/null 2>&1; then
    radeontop -d - -l 1 2>/dev/null | grep -oP 'vram \K[0-9]+' | head -n1
    exit 0
fi

echo "N/A"
