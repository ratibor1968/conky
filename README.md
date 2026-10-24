# conky

A pair of [Conky](https://github.com/brndnmtthws/conky) panels for a KDE/Wayland
desktop, styled with the Catppuccin Mocha palette.

| Panel | Position | Config |
|-------|----------|--------|
| System | top-right | `conky.conf` |
| Network | top-left | `conky_network.conf` |

## Features

**System panel**
- Clock, date and uptime in a header block.
- CPU model, live usage graph, total usage bar and CPU **package power** (W)
  read from the RAPL energy counter.
- CPU temperature from the CPU's own `k10temp` (`Tctl`) / `coretemp` sensor.
- Adaptive per-CPU grid: it detects how many logical CPUs are online and lays
  itself out automatically — so it follows BIOS **X3D mode** (e.g. 6 cores vs
  12 cores / 24 threads) with no edits.
- Grid is grouped into **physical cores** and **SMT threads**, with values
  right-aligned so the `%` stays next to the bar.
- GPU (NVIDIA or AMD) usage, temperature, power draw and a usage graph, plus
  VRAM usage.
- Memory, swap and root filesystem usage, and disk I/O rates plus
  auto-scaling read/write graphs for the device backing `/`.
- Usage bars (CPU total, RAM, root, VRAM) are accent blue normally and switch
  to amber/red past 75%/90%.

**Network panel**
- The **active interface is detected at runtime** (default-route device), so
  switching between wired and Wi-Fi is followed live — no restart.
- Link block with interface type, address and gateway; Wi-Fi adds the SSID and
  signal strength.
- Live up/down graphs and transfer totals for the active link. Speeds are
  labelled with explicit per-second units (e.g. `12.3 MiB/s`).
- Established-connection peers grouped by **reverse-DNS hostname** (cached and
  resolved with a short timeout, so the panel never blocks). Internet peers
  collapse to their registrable domain, one row per provider. Peers on a private
  network are never collapsed: the router names every DHCP client under its own
  domain (`bitaxe1.fritz.box`), so collapsing would draw several devices as one
  `fritz.box` row that reads like traffic to the gateway. Those rows keep the
  device name plus its address (`bitaxe1@192.168.178.62`) and are drawn in teal.
- A top-process list aggregated by name and ranked by **instantaneous CPU%**:
  the delta of `/proc` tick counters between refreshes, so an idle process
  drops off immediately instead of coasting on its lifetime average. CPU is a
  share of total capacity (all cores pegged = 100%), i.e. it can never exceed
  100%. Each row also shows RSS, the process's established-connection count
  (`CONN`) and a GPU marker. The process name is colour-coded by load — white
  at idle, cyan at one core, purple at two, bright purplish pink from three
  cores up — with one colour step per whole percent of CPU share.

## Requirements

- `conky` (built with Xft; `nvidia` support recommended)
- `lm_sensors` (for CPU temperature)
- `nvidia-smi` (NVIDIA GPUs) and/or `radeontop` (AMD GPUs)
- `otf-font-awesome` (panel icons)
- Fonts: **Fira Sans**, **Noto Sans Mono**

On Arch/CachyOS:

```sh
sudo pacman -S conky lm_sensors otf-font-awesome ttf-fira-sans noto-fonts nvidia-utils
```

## Usage

```sh
./conky_start.sh
```

The script (re)starts both panels and is safe to run repeatedly. The network
panel detects the active interface at runtime, so nothing is rendered per
login. Set `CONKY_IFACE` / `CONKY_DISK` to override interface / disk device
detection (both are exported to the panels).

### Refresh rate

Both panels run at `update_interval = 2` (2 s), with the sampler on the same
tick. Conky accepts fractional intervals — 0.1 s was measured working — and
1 s also runs fine, but 2 s is the default: the `execi`/`execpi` intervals
are whole seconds, so a faster refresh mostly re-renders identical data for
extra CPU.

### Resource use

The expensive probes (process table, CPU grid) are precomputed by a small
long-lived **sampler** (`bin/conky_sampler.sh`) that writes state files every
two seconds; the panels just read them. This avoids forking a shell per value
on every refresh, and pairs with short on-disk caches for the GPU sample, the
process list's connection/GPU columns and the reverse-DNS/ASN lookups (each
host is resolved once and reused).

`conky_start.sh` starts the sampler automatically: as a `systemd --user`
service (`conky-sampler.service`) when systemd is available, otherwise as a
background process. At the 2 s cadence the two panels plus the sampler use on
the order of 15-20% of one core (≲1% of a 24-thread machine).

### Autostart

Add `~/.conky/conky_start.sh` to your autostart entries (KDE: *System Settings →
Autostart*).

> **KDE users — important:** also exclude the panels from session restoration,
> otherwise Plasma relaunches its own copies at login in addition to this
> autostart entry, doubling the panels on every login. In *System Settings →
> Session → Desktop Session → Applications to be excluded from session
> restoration* add `conky` (equivalently: `excludeApps=conky,ConkySystem,ConkyNet`
> under `[General]` in `~/.config/ksmserverrc`).

### Triaging a connection

The panel groups connections, so it hides ports, addresses and processes. When a
CONNECTIONS row needs explaining, `bin/conky_net_peers_detail.sh` prints one row
per established socket: address, remote port, resolved name and the owning local
process. `bin/conky_net_peers.sh --self-test` re-checks the host-labelling rules
after any edit to that script.

## Layout

```
conky.conf            system panel
conky_network.conf    network panel
conky_start.sh        start both panels
bin/                  helper scripts called from the configs
run/                  runtime lock file (git-ignored)
```

## Notes

- CPU package power is derived from `/sys/class/powercap/intel-rapl:0/energy_uj`
  (world-readable on most systems) using a small state file; it prints `N/A` if
  RAPL is unavailable.
- Temperature and usage helpers fall back to `N/A` rather than failing.
