#!/bin/bash
# Top processes aggregated by command name, rendered as conky markup
# (consumed with ${execpi} from the network panel).
#
#   CPU%  is INSTANTANEOUS: the delta of /proc/<pid>/stat CPU-tick counters
#         between consecutive runs (~the sampler cadence), not ps's average
#         since the process started. A process that goes idle drops out of
#         the list on the next refresh instead of coasting on history for
#         hours. The value is a share of the WHOLE CPU (all cores pegged =
#         100%, one pinned core on a 24-thread CPU = ~4.2%), the same unit as
#         the panel's CPU reading -- so it can never exceed 100 and needs no
#         display clamp. The process name is colour-coded along a white ->
#         cyan -> purple -> bright purplish pink ramp, one colour step per
#         whole percent of CPU share: white at idle, cyan at one core (4%),
#         purple at two, bright purplish pink from three cores up.
#   MEM   current resident memory, summed across instances of the same name.
#   CONN  established, non-loopback TCP connections owned by the process
#         (from `ss`), so the connection view and the process view agree.
#   GPU   marks processes that currently hold the GPU (nvidia-smi pmon).
#
# The process scan runs on every call; the two comparatively expensive probes
# (ss, pmon) are cached for a few seconds, and the rendered output for
# CACHE_MS, so the panel cadence stays cheap even in sampler-dead fallback
# mode.
#
# PID reuse is detected via the process start time: a PID whose start time
# differs from the snapshot counts as a fresh process, so it can never inherit
# another process's ticks.
set -u

LIMIT=18          # rows to display
NAME=11           # visible width of the name column (keeps a row inside 240px)
CACHE_MS=400      # rendered-output cache (ms)
CONNS_TTL_MS=3000 # re-run `ss` at most this often (ms)
GPU_TTL_MS=5000   # re-run `nvidia-smi pmon` at most this often (ms)
HZ=100            # USER_HZ: /proc/<pid>/stat ticks per second

DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
RUN="${XDG_RUNTIME_DIR:-/tmp}"
OUT="$RUN/conky_top_procs.cache"   # rendered markup for the panel
SNAP="$RUN/conky_top_procs.snap"   # last /proc snapshot (delta baseline)
CONNS="$RUN/conky_top_procs.conns" # cached per-command connection counts
GPUC="$RUN/conky_top_procs.gpu"    # cached pmon process list

now_ms=$(date +%s%3N)

# Fast path: conky may call more than once per sampler tick.
if [ -r "$OUT" ]; then
    read -r ts <"$OUT" || ts=0
    if [ "$ts" -gt 0 ] && [ $((now_ms - ts)) -lt "$CACHE_MS" ]; then
        tail -n +2 "$OUT"
        exit 0
    fi
fi

# One /proc snapshot, tab separated: pid, ticks, rss (KiB), start time, comm.
# The comm field is delimited by the first '(' and the LAST ')' of the stat
# line, which is robust for names containing spaces or parentheses.
#
# The file list goes to `cat`, not to awk directly: gawk aborts on the first
# file that vanished between glob expansion and open (common when processes
# exit during a fork storm) and silently drops every process after it in the
# argument list, which poisoned the delta baseline. cat just warns (silenced)
# and moves on to the next file.
snapshot() {
    cat /proc/[0-9]*/stat 2>/dev/null | awk '
    {
        pid = $1
        sub(/^[0-9]+ /, "")
        j = 0
        for (k = length($0); k > 0; k--) if (substr($0, k, 1) == ")") { j = k; break }
        if (j == 0) next
        comm = substr($0, 2, j - 2)
        gsub(/\t/, " ", comm)
        n = split(substr($0, j + 2), f, " ")
        print pid "\t" (f[12] + f[13]) "\t" (f[22] * 4) "\t" f[20] "\t" comm
    }'
}

# Delta baseline: the previous snapshot, or a fresh one taken 200 ms back when
# there is none or it is stale (after a suspend/resume gap the ticks would
# otherwise be averaged over the whole gap and every value washed out).
prev_ts=0
if [ -r "$SNAP" ]; then
    IFS=$'\t' read -r tag prev_ts <"$SNAP" || true
    [ "${tag:-}" = "ts" ] || prev_ts=0
fi

# Re-take the baseline 200 ms back: used on first run, after a stale-state gap
# (suspend/resume), and when the stored baseline looks truncated.
cold_baseline() {
    prev="$SNAP.prev.$$"
    { printf 'ts\t%s\n' "$now_ms"; printf '%s\n' "$1"; } >"$prev" 2>/dev/null ||
        { rm -f "$prev"; exit 0; }
    prev_ts=$now_ms
    sleep 0.2
    body=$(snapshot)
    t2=$(date +%s%3N)
    dt_ms=$(( t2 - prev_ts ))
    [ "$dt_ms" -gt 0 ] || dt_ms=1
}

body=$(snapshot)
t2=$now_ms
prev="$SNAP"
if [ "${prev_ts:-0}" -le 0 ] || [ $((now_ms - prev_ts)) -gt 30000 ]; then
    cold_baseline "$body"
else
    # Insurance: a baseline missing a large chunk of the process list would
    # make every missing process look brand new and show its lifetime ticks as
    # one interval's usage (the runaway-percentage glitch). Re-baseline instead.
    plines=$(wc -l <"$prev" 2>/dev/null || echo 0)
    blines=$(printf '%s\n' "$body" | wc -l)
    if [ "${plines:-0}" -lt $(( blines * 3 / 4 )) ]; then
        cold_baseline "$body"
    fi
    dt_ms=$(( t2 - prev_ts ))
    [ "$dt_ms" -gt 0 ] || dt_ms=1
fi

# Per-command established connection counts, cached for CONNS_TTL_MS.
conns="$CONNS"
cts=0
[ -r "$conns" ] && { read -r cts <"$conns" || cts=0; }
if [ "${cts:-0}" -le 0 ] || [ $((now_ms - cts)) -ge "$CONNS_TTL_MS" ]; then
    tmp="$CONNS.$$"
    {
        printf '%s\n' "$now_ms"
        ss -Htnp state established 2>/dev/null | awk '
        {
            if ($4 ~ /^\[/) { sub(/\]:[0-9]*$/, "", $4) } else { sub(/:[0-9]*$/, "", $4) }
            host = $4
            gsub(/^\[|\]$/, "", host); sub(/^::ffff:/, "", host)
            if (host == "" || host == "*" || host == "0.0.0.0") next
            if (host == "::1" || host ~ /^127\./) next
            name = "?"
            if (match($0, /users:\(\("/)) {
                rest = substr($0, RSTART + 9)
                p = index(rest, "\"")
                if (p > 0) name = substr(rest, 1, p - 1)
            }
            cnt[name]++
        }
        END { for (k in cnt) printf "%d\t%s\n", cnt[k], k }'
    } >"$tmp" 2>/dev/null && mv -f "$tmp" "$CONNS"
    rm -f "$tmp"
fi
[ -r "$conns" ] || conns=/dev/null

# GPU process list, cached for GPU_TTL_MS (pmon is the most expensive probe).
gpu="$GPUC"
gts=0
[ -r "$gpu" ] && { read -r gts <"$gpu" || gts=0; }
if [ "${gts:-0}" -le 0 ] || [ $((now_ms - gts)) -ge "$GPU_TTL_MS" ]; then
    tmp="$GPUC.$$"
    {
        printf '%s\n' "$now_ms"
        timeout 3 nvidia-smi pmon -c 1 2>/dev/null | awk '!/^#/ && $NF != "" { print $NF }'
    } >"$tmp" 2>/dev/null && mv -f "$tmp" "$GPUC"
    rm -f "$tmp"
fi
[ -r "$gpu" ] || gpu=/dev/null

# Merge, aggregate and render.
rendered=$(printf '%s\n' "$body" | awk \
    -v prevf="$prev" -v connsf="$conns" -v gpuf="$gpu" \
    -v dt="$dt_ms" -v hz="$HZ" -v namew="$NAME" -v limit="$LIMIT" '
BEGIN {
    FS = "\t"
    # Online CPU count (respects X3D mode switches): CPU shares are divided
    # by this, so the column is bounded by 100.
    nproc = 0
    while ((getline l < "/proc/stat") > 0) if (l ~ /^cpu[0-9]+ /) nproc++
    close("/proc/stat")
    if (nproc < 1) nproc = 1
    while ((getline l < prevf) > 0) {
        split(l, a, "\t")
        if (a[1] == "ts") continue
        pticks[a[1]] = a[2] + 0
        pstart[a[1]] = a[4]
    }
    close(prevf)
    while ((getline l < connsf) > 0) {
        split(l, a, "\t")
        if (a[1] == "" || a[1] == "ts") continue
        cconn[a[2]] += a[1] + 0
    }
    close(connsf)
    while ((getline l < gpuf) > 0) {
        if (l == "" || l ~ /^[0-9]+$/) continue
        gset[l] = 1
    }
    close(gpuf)
}
{
    pid = $1; ticks = $2 + 0; rss = $3 + 0; start = $4; comm = $5
    secs = dt / 1000.0
    if (pid in pticks && pstart[pid] == start)
        pct = (ticks - pticks[pid]) / hz / secs * 100.0
    else
        pct = ticks / hz / secs * 100.0   # born within the interval (or PID reused)
    if (pct < 0) pct = 0
    cpu[comm] += pct
    mem[comm] += rss
    if (!(comm in seen)) { seen[comm] = 1; order[++nn] = comm }
}
END {
    for (i = 1; i <= nn; i++)
        for (j = i + 1; j <= nn; j++) {
            x = order[i]; y = order[j]
            if (cpu[y] > cpu[x] || (cpu[y] == cpu[x] && mem[y] > mem[x])) { order[i] = y; order[j] = x }
        }
    printf "${color7}%-*s${alignr}%6s %5s %4s %-3s${color}\n", namew, "NAME", "CPU%", "MEM", "CONN", "GPU"
    for (i = 1; i <= nn && i <= limit; i++) {
        nm = order[i]
        disp = (length(nm) > namew) ? substr(nm, 1, namew - 3) "..." : nm
        r = mem[nm] / 1024
        m = (r >= 1024) ? sprintf("%.1fG", r / 1024) : sprintf("%.0fM", r)
        # Share of total CPU capacity; capped only against sample-timing skew.
        c = cpu[nm] / nproc
        if (c > 100) c = 100
        cpuf = sprintf("%.1f%%", c)
        # Name colour, stepped on the displayed whole percent (so the colour
        # changes exactly when the number crosses a whole %): white below one
        # core, max cyan at 4% (one core), then purple (8%, two cores) and
        # bright purplish pink (12%, three cores) with the last segment
        # clamped for anything above.
        q = int(sprintf("%.1f", c) + 0)
        if (q > 12) q = 12
        if (q < 0) q = 0
        if (q <= 4)      { t = q / 4;       r1 = 255; g1 = 255; b1 = 255; r2 = 137; g2 = 220; b2 = 235 }
        else if (q <= 8) { t = (q - 4) / 4; r1 = 137; g1 = 220; b1 = 235; r2 = 203; g2 = 166; b2 = 247 }
        else             { t = (q - 8) / 4; r1 = 203; g1 = 166; b1 = 247; r2 = 255; g2 = 124; b2 = 240 }
        cc = sprintf("${color #%02X%02X%02X}", int(r1 + t * (r2 - r1) + 0.5), int(g1 + t * (g2 - g1) + 0.5), int(b1 + t * (b2 - b1) + 0.5))
        cn = (cconn[nm] > 0) ? sprintf("%d", cconn[nm]) : ""
        gcol = (nm in gset) ? "${color8}●${color3}  " : "   "
        printf "%s%-*s${color3}${alignr}%6s %5s %4s %s${color}\n", cc, namew, disp, cpuf, m, cn, gcol
    }
}')

# Persist the new baseline (the delta source) and the rendered cache.
tmp="$SNAP.$$"
{ printf 'ts\t%s\n' "$t2"; printf '%s\n' "$body"; } >"$tmp" 2>/dev/null && mv -f "$tmp" "$SNAP" 2>/dev/null
rm -f "$tmp"
[ "$prev" = "$SNAP" ] || rm -f "$prev"

tmp="$OUT.$$"
{ printf '%s\n' "$now_ms"; printf '%s\n' "$rendered"; } >"$tmp" 2>/dev/null && mv -f "$tmp" "$OUT" 2>/dev/null
rm -f "$tmp"

printf '%s\n' "$rendered"
