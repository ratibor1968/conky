#!/bin/bash
# GPU VRAM usage in percent (no unit). Reads the shared GPU sampler (one
# nvidia-smi call covers every GPU field), falling back to AMD, else N/A.
#
# Usage: conky_gpu_vram.sh [color]
#   (none)  print the bare percentage (or N/A)
#   color   print the conky colour markup for the usage bar: accent below 75%,
#           warning 75-89%, critical 90%+. N/A stays accent so a missing GPU
#           does not look like a full one.
set -u
DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

val=""
if command -v nvidia-smi >/dev/null 2>&1; then
    v=$("$DIR/conky_gpu_sample.sh" vram)
    [ -n "$v" ] && [ "$v" != "N/A" ] && val="$v"
fi
if [ -z "$val" ] && command -v radeontop >/dev/null 2>&1; then
    val=$(radeontop -d - -l 1 2>/dev/null | grep -oP 'vram \K[0-9]+' | head -n1)
fi
[ -n "$val" ] || val="N/A"

if [ "${1:-}" = color ]; then
    if [ "$val" = "N/A" ]; then c=color1
    elif [ "$val" -ge 90 ] 2>/dev/null; then c=color5
    elif [ "$val" -ge 75 ] 2>/dev/null; then c=color4
    else c=color1
    fi
    printf '${%s}' "$c"
else
    printf '%s\n' "$val"
fi
