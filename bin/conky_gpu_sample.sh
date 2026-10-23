#!/usr/bin/env bash
# Shared GPU sampler: collects every GPU value we display in one place and
# caches the result for a couple of seconds. All the per-field helpers read
# this cache instead of each spawning their own query, which is what caused
# several identical calls per refresh.
#
# NVIDIA: one `nvidia-smi` query covers every field.
# AMD:    the amdgpu sysfs interface is cheap and does not need radeontop:
#           gpu_busy_percent, mem_info_vram_{used,total},
#           hwmon/{temp1_input,power1_input}, and lspci for the model name.
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

write_state() { # $1 = state text
    local tmp="${STATE}.$$"
    printf '%s\n' "$1" >"$tmp" 2>/dev/null && mv -f "$tmp" "$STATE" 2>/dev/null
}

nvidia_sample() {
    command -v nvidia-smi >/dev/null 2>&1 || return 1

    local line name usage temp power mused mtotal vram
    line=$(timeout 3 nvidia-smi \
        --query-gpu=name,utilization.gpu,temperature.gpu,power.draw,memory.used,memory.total \
        --format=csv,noheader,nounits 2>/dev/null | head -n1)
    [ -n "$line" ] || return 1

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

    printf '%s\nname=%s\nusage=%s\ntemp=%s\npower=%s\nvram=%s\n' \
        "$now_ms" "${name:-N/A}" "${usage:-N/A}" "${temp:-N/A}" \
        "${power:-N/A}" "${vram:-N/A}"
}

amd_sample() {
    local d vendor card h name usage temp power used total vram slot raw codename marketing

    for d in /sys/class/drm/card*/device; do
        [ -r "$d/vendor" ] || continue
        vendor=$(cat "$d/vendor" 2>/dev/null)
        [ "$vendor" = "0x1002" ] || continue

        card=${d%/device}
        card=${card##*/}

        usage=$(cat "$d/gpu_busy_percent" 2>/dev/null)
        used=$(cat "$d/mem_info_vram_used" 2>/dev/null)
        total=$(cat "$d/mem_info_vram_total" 2>/dev/null)
        vram=""
        if [ -n "$used" ] && [ -n "$total" ] && [ "$total" -gt 0 ] 2>/dev/null; then
            vram=$(awk -v u="$used" -v t="$total" 'BEGIN{printf "%.0f", u/t*100}')
        fi

        temp=""
        power=""
        for h in "$d"/hwmon/hwmon*; do
            [ -r "$h/temp1_input" ] && temp=$(awk -v v="$(cat "$h/temp1_input")" 'BEGIN{printf "%.1f", v/1000}')
            [ -r "$h/power1_input" ] && power=$(awk -v v="$(cat "$h/power1_input")" 'BEGIN{printf "%.0f", v/1e6}')
        done

        # Friendly short name from lspci, e.g. "Radeon RX Vega 6 (Renoir)".
        slot=$(basename "$(readlink -f "$d")")
        raw=$(lspci -s "${slot#0000:}" 2>/dev/null | sed -E 's/^[^ ]+ [^:]+: //')
        name=""
        if [ -n "$raw" ]; then
            raw=$(printf '%s' "$raw" | sed -E \
                's/^Advanced Micro Devices, Inc\. \[AMD\/ATI\] //; s/ \[[0-9a-fA-F]{4}:[0-9a-fA-F]{4}\]//; s/ \(rev [^)]*\)$//')
            codename=${raw%% *}
            marketing=$(printf '%s' "$raw" | sed -n 's/^[^[]*\[\([^]]*\)\].*/\1/p' | sed 's/ (.*//')
            if [ -n "$marketing" ]; then
                name="$marketing ($codename)"
            else
                name=$(printf '%s' "$raw" | cut -c1-38)
            fi
        fi

        printf '%s\nname=%s\nusage=%s\ntemp=%s\npower=%s\nvram=%s\n' \
            "$now_ms" "${name:-N/A}" "${usage:-N/A}" "${temp:-N/A}" \
            "${power:-N/A}" "${vram:-N/A}"
        return 0
    done
    return 1
}

if [ "$fresh" -eq 0 ]; then
    body=$(nvidia_sample) || body=$(amd_sample) || body=""
    [ -n "$body" ] && write_state "$body"
fi

key="${1:-}"
if [ -z "$key" ]; then
    [ -r "$STATE" ] && cat "$STATE"
    exit 0
fi
[ -r "$STATE" ] || { echo "N/A"; exit 0; }
awk -F= -v k="$key" '$1==k { print $2; found=1; exit } END { if (!found) print "N/A" }' "$STATE" 2>/dev/null
