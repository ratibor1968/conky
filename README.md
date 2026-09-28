# conky

A pair of [Conky](https://github.com/brndnmtthws/conky) panels for a KDE/Wayland
desktop, styled with the Catppuccin Mocha palette.

| Panel | Position | Config |
|-------|----------|--------|
| System | top-right | `conky.conf` |
| Network | top-left | `conky_network.conf` (template) |

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
- Memory, swap, root filesystem and a top-process list aggregated by name.

**Network panel**
- Interface, address and gateway.
- Live up/down graphs, transfer totals and established-connection peers
  grouped by remote host.

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

The script detects the primary network interface, renders
`conky_network.conf` into `run/conky_network.conf`, and (re)starts both panels.
It is safe to run repeatedly. Set `CONKY_IFACE` to override interface
detection.

### Autostart

Add `~/.conky/conky_start.sh` to your autostart entries (KDE: *System Settings →
Autostart*).

> **KDE users — important:** also exclude the panels from session restoration,
> otherwise Plasma relaunches its own copies at login in addition to this
> autostart entry, doubling the panels on every login. In *System Settings →
> Session → Desktop Session → Applications to be excluded from session
> restoration* add `conky` (equivalently: `excludeApps=conky,ConkySystem,ConkyNet`
> under `[General]` in `~/.config/ksmserverrc`).

## Layout

```
conky.conf            system panel
conky_network.conf    network panel template (@IFACE@ placeholder)
conky_start.sh        start both panels, render the network template
bin/                  helper scripts called from the configs
run/                  generated files (git-ignored)
```

## Notes

- CPU package power is derived from `/sys/class/powercap/intel-rapl:0/energy_uj`
  (world-readable on most systems) using a small state file; it prints `N/A` if
  RAPL is unavailable.
- Temperature and usage helpers fall back to `N/A` rather than failing.
