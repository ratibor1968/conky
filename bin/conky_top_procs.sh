#!/bin/bash
# Top processes aggregated by command name (CPU% and RSS summed across
# instances) so the same binary never appears several times. A GPU column
# marks processes that currently hold the GPU. Output is conky markup,
# consumed with ${execpi}.
#
# This is the most expensive helper (it shells out to `ps` and `nvidia-smi
# pmon`), so its rendered output is cached briefly: conky may ask every 2-3s,
# but the underlying commands run at most once per CACHE_MS.
#
# GPU detection comes from `nvidia-smi pmon`, which lists every process with an
# open GPU context (including plain graphics clients) regardless of whether the
# driver reports a per-process utilisation percentage. The pmon command names
# are truncated exactly like `ps -eo comm`, so they match the aggregation key.

set -u

CACHE_MS=1000
STATE="${XDG_RUNTIME_DIR:-/tmp}/conky_top_procs.cache"
now_ms=$(date +%s%3N)

if [ -r "$STATE" ]; then
    read -r ts <"$STATE" 2>/dev/null || ts=0
    if [ "$ts" -gt 0 ] && [ $((now_ms - ts)) -lt "$CACHE_MS" ]; then
        tail -n +2 "$STATE"
        exit 0
    fi
fi

render() {
    local gpu_names
    gpu_names=$(timeout 3 nvidia-smi pmon -c 1 2>/dev/null |
        awk '!/^#/ && NF >= 10 && $10 != "" { print $10 }')

    ps -eo comm=,pcpu=,rss= --sort=-pcpu 2>/dev/null | awk -v gpu="$gpu_names" '
    BEGIN {
        g = split(gpu, arr, "\n")
        for (i = 1; i <= g; i++) if (arr[i] != "") gset[arr[i]] = 1
        NAME=16   # visible width of the name column; longer names get "..."
    }
    {
        name = $1; cpu = $2; rss = $3
        c[name] += cpu; m[name] += rss
        if (!(name in seen)) { seen[name] = 1; order[++nn] = name }
    }
    END {
        for (i = 1; i <= nn; i++)
            for (j = i + 1; j <= nn; j++)
                if (c[order[j]] > c[order[i]]) { t = order[i]; order[i] = order[j]; order[j] = t }

        printf "${color7}%-*s${alignr}%6s %5s %-3s${color}\n", NAME, "NAME", "CPU%", "MEM", "GPU"
        for (i = 1; i <= nn && i <= 8; i++) {
            nm = order[i]
            # Truncate for display only; look up metrics by the original key.
            disp = (length(nm) > NAME) ? substr(nm, 1, NAME - 3) "..." : nm
            r = m[nm] / 1024
            mem = (r >= 1024) ? sprintf("%.1fG", r / 1024) : sprintf("%.0fM", r)
            cpuf = sprintf("%.1f%%", c[nm])
            # Right group: CPU% MEM GPU with single-space gaps. The GPU field is
            # a single visible char (dot or blank) padded to 3 before any
            # colour markup, so the width counting stays correct.
            gcol = (nm in gset) ? "${color8}●${color3}  " : "   "
            printf "${color2}%-*s${color3}${alignr}%6s %5s %s${color}\n", NAME, disp, cpuf, mem, gcol
        }
    }'
}

body=$(render)
tmp="${STATE}.$$"
{ printf '%s\n' "$now_ms"; printf '%s\n' "$body"; } >"$tmp" 2>/dev/null &&
    mv -f "$tmp" "$STATE" 2>/dev/null
printf '%s\n' "$body"
