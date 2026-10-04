#!/bin/bash
# Emits the CPU usage block as conky markup (consumed with ${execpi}):
#   * a full-width TOTAL usage bar aligned with the grid columns
#   * the per-CPU grid, grouped into PHYSICAL CORES and SMT THREADS
#
# The number of online CPUs changes with the X3D mode (e.g. 6 vs 24) and SMT
# may be on/off, so nothing is hardcoded: the grid adapts at runtime.
#
# Set CONKY_CPU_LIST (e.g. "0-5") to override detection for testing.
set -u

CONTENT=240          # usable content width (= window width, so the CPU grid/bars line up with the panel's alignr edge)
X0=16                # border_inner_margin: plain text starts here, ${goto} uses the
                     # window origin, so every goto is shifted by this much
LABELW=3             # label field width ("C1 " / "C12"), keeps values in a column
VALW=30              # value field width in px ("100%" ~29px), right-aligned
BAROFF=52            # bar offset from cell start (after label + value)
BARW=16              # compact bar width
GAP=10               # gap after the bar / between cells

raw="${CONKY_CPU_LIST:-$(cat /sys/devices/system/cpu/online 2>/dev/null)}"
[ -n "$raw" ] || raw="0"

# Expand a CPU list like "0-5,8,10-12" to one index per line (ascending).
mapfile -t all < <(awk -v l="$raw" 'BEGIN{
    n = split(l, p, ",")
    for (i = 1; i <= n; i++) {
        if (p[i] ~ /-/) { split(p[i], r, "-"); for (j = r[1]+0; j <= r[2]+0; j++) print j }
        else if (p[i] != "") print p[i]+0
    }
}')
[ "${#all[@]}" -gt 0 ] || exit 0

declare -A online=()
for c in "${all[@]}"; do online[$c]=1; done

# Split into physical cores (lowest online sibling) and SMT threads.
phys=(); smt=()
for c in "${all[@]}"; do
    sib=$(cat "/sys/devices/system/cpu/cpu$c/topology/thread_siblings_list" 2>/dev/null)
    [ -n "$sib" ] || sib="$c"
    m=""
    IFS=',' read -ra parts <<< "$sib"
    for s in "${parts[@]}"; do
        [ -n "${online[$s]:-}" ] || continue
        if [ -z "$m" ] || [ "$s" -lt "$m" ]; then m="$s"; fi
    done
    [ -n "$m" ] || m="$c"
    if [ "$c" = "$m" ]; then phys+=("$c"); else smt+=("$c"); fi
done

# Grid geometry, derived from the largest group so both groups line up.
maxn=${#phys[@]}
[ "${#smt[@]}" -gt "$maxn" ] && maxn=${#smt[@]}
if [ "$maxn" -le 6 ]; then cols=2; else cols=3; fi
# Cell pitch: distribute CONTENT across the columns exactly, so the *last*
# bar's right edge lands on X0 + CONTENT (the same edge ${alignr} and the
# full-width graphs use). Each cell packs "C1 3% |bar|" tightly; the leftover
# space becomes the gap before the next cell.
cellw=$(( CONTENT / cols ))
# The last cell's bar start is shifted so bar_start + BARW == X0 + CONTENT.
lastbaroff=$(( CONTENT - (cols - 1) * cellw - BARW ))

# One grid line per row; cells are absolutely positioned with ${goto}.
emit_grid() { # $1=colour number, $2=label prefix, rest=CPU list
    local col="$1" prefix="$2"; shift 2
    local arr=("$@") n=${#arr[@]} i=0 c colidx
    [ "$n" -gt 0 ] || return 0
    for c in "${arr[@]}"; do
        colidx=$(( i % cols ))
        if [ "$colidx" -eq 0 ]; then
            [ "$i" -gt 0 ] && printf '\n'
            printf '${font Noto Sans Mono:size=9}'
        else
            printf '${goto %d}' "$(( X0 + colidx * cellw ))"
        fi
        # Compact cell: "C1 3% |bar|". The bar start differs per column (the
        # last one is shifted right to keep the grid flush), so the value is
        # placed via ${goto} just before its bar instead of right after the
        # label -- otherwise the last column would show a gap before its bar.
        printf '${color%s}%-*s' "$col" "$LABELW" "$prefix$(( i + 1 ))"
        # Pick this column's bar offset, then right-align the value in a fixed
        # 4-char field ending a couple of pixels before the bar.
        if [ "$colidx" -eq "$(( cols - 1 ))" ]; then
            boff=$lastbaroff
        else
            boff=$BAROFF
        fi
        printf '${goto %d}${color3}' "$(( X0 + colidx * cellw + boff - VALW ))"
        printf '${if_match ${cpu cpu%d} < 100} ${endif}${if_match ${cpu cpu%d} < 10} ${endif}${cpu cpu%d}%%' \
            "$c" "$c" "$c"
        printf '${goto %d}${color%s}${cpubar cpu%d 6,%d}' \
            "$(( X0 + colidx * cellw + boff ))" "$col" "$c" "$BARW"
        i=$(( i + 1 ))
    done
    printf '\n'
}

# TOTAL: a full-width usage bar, aligned with the CPU/GPU graphs.
printf '${voffset 9}${color2}TOTAL${goto %d}${color1}${cpubar 6,%d}\n' \
    "$(( X0 + BAROFF ))" "$(( CONTENT - BAROFF ))"

if [ "${#smt[@]}" -gt 0 ]; then
    printf '${voffset 8}${font Fira Sans:Bold:size=8}${color7}PHYSICAL CORES\n'
    emit_grid 1 C "${phys[@]}"
    printf '${voffset 8}${font Fira Sans:Bold:size=8}${color7}SMT THREADS\n'
    emit_grid 8 T "${smt[@]}"
else
    printf '${voffset 8}${font Fira Sans:Bold:size=8}${color7}PHYSICAL CORES\n'
    emit_grid 1 C "${all[@]}"
fi
