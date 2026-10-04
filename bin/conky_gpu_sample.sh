#!/usr/bin/env bash
# Shared GPU sampler: runs a single `nvidia-smi` query for every GPU value we
# display and caches the result for a couple of seconds. All the per-field
# helpers read this cache instead of each spawning their own `nvidia-smi`, which
# is what caused several identical calls per refresh.
#
# Usage: conky_gpu_sample.sh            # refresh if stale, then print key=value
#        conky_gpu_sample.sh <key>      # print one value (refreshing if stale)
#
# Keys: usage temp power vram name
set -u

STATE="${XDG_RUNTIME_DIR:-/tmp}/conky_gpu.state"
MIN_AGE_MS=1500   # don't re-query within this window (covers one refresh cycle)

now_ms=$(date +%s%3N)
fresh=0
if [ -r "$STATE" ]; then
    read -r ts <"$STATE" 2>/dev/null || ts=0
    [ $((now_ms - ts)) -lt "$MIN_AGE_MS" ] && fresh=1
fi

if [ "$fresh" -eq 0 ]; then
    tmp="${STATE}.$$"
    if command -v nvidia-smi >/dev/null 2>&1; then
        # One query, all fields.
        line=$(timeout 3 nvidia-smi \
            --query-gpu=name,utilization.gpu,temperature.gpu,power.draw,memory.used,memory.total \
            --format=csv,noheader,nounits 2>/dev/null | head -n1)
        if [ -n "$line" ]; then
            name=$(printf '%s' "$line" | cut -d, -f1 | sed 's/^ *//; s/ *$//')
            usage=$(printf '%s' "$line" | cut -d, -f2 | tr -dc '0-9.')
            temp=$(printf '%s' "$line" | cut -d, -f3 | tr -dc '0-9.')
            power=$(printf '%s' "$line" | cut -d, -f4 | tr -dc '0-9.')
            mused=$(printf '%s' "$line" | cut -d, -f5 | tr -dc '0-9')
            mtotal=$(printf '%s' "$line" | cut -d, -f6 | tr -dc '0-9')
            vram=""
            if [ -n "$mtotal" ] && [ "$mtotal" -gt 0 ] 2>/dev/null; then
                vram=$(awk -v u="$mused" -v t="$mtotal" 'BEGIN{printf "%.0f", u/t*100}')
            fi
            {
                printf '%s\n' "$now_ms"
                printf 'name=%s\n' "${name:-N/A}"
                printf 'usage=%s\n' "${usage:-N/A}"
                printf 'temp=%s\n' "${temp:-N/A}"
                printf 'power=%s\n' "${power:-N/A}"
                printf 'vram=%s\n' "${vram:-N/A}"
            } >"$tmp" 2>/dev/null && mv -f "$tmp" "$STATE" 2>/dev/null
        fi
    fi
fi

key="${1:-}"
if [ -z "$key" ]; then
    cat "$STATE" 2>/dev/null
    exit 0
fi
awk -F= -v k="$key" '$1==k { print $2; found=1; exit } END { if (!found) print "N/A" }' "$STATE" 2>/dev/null
