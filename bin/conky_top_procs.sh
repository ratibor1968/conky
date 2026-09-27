#!/bin/bash
# Top processes aggregated by command name (CPU% and RSS summed across
# instances) so the same binary never appears several times. Output is
# conky markup, consumed with ${execpi}.
ps -eo comm=,pcpu=,rss= --sort=-pcpu 2>/dev/null | awk '
{
    name = $1; cpu = $2; rss = $3
    c[name] += cpu; m[name] += rss
    if (!(name in seen)) { seen[name] = 1; order[++n] = name }
}
END {
    for (i = 1; i <= n; i++)
        for (j = i + 1; j <= n; j++)
            if (c[order[j]] > c[order[i]]) { t = order[i]; order[i] = order[j]; order[j] = t }

    printf "${color7}%-20.20s %6s %6s${color}\n", "NAME", "CPU%", "MEM"
    for (i = 1; i <= n && i <= 8; i++) {
        nm = order[i]
        r = m[nm] / 1024
        mem = (r >= 1024) ? sprintf("%.1fG", r / 1024) : sprintf("%.0fM", r)
        printf "${color2}%-20.20s${color3} %5.1f%% %6s${color}\n", nm, c[nm], mem
    }
}'
