# conky

A pair of [Conky](https://github.com/brndnmtthws/conky) panels styled with the
Catppuccin Mocha palette.

| Panel | Position | Config |
|-------|----------|--------|
| System | top-right | `conky.conf` |
| Network | top-left | `conky_network.conf` |

The configs work on both KDE/Wayland and Cinnamon/X11. Window type and
transparency are selected at runtime from `XDG_SESSION_TYPE`: Cinnamon/X11 uses
a compositor-friendly `dock` window with a real ARGB background, while
KDE/Wayland keeps the existing `normal` window settings.

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
- Memory, swap, root filesystem, a top-process list aggregated by name, with a
  GPU marker for processes currently holding the GPU.
- Battery section (charge, state, power draw, remaining time) shown
  automatically when an ACPI battery is present.

**Network panel**
- The **active interface is detected at runtime** (default-route device), so
  switching between wired and Wi-Fi is followed live — no restart.
- Link block with interface type, address and gateway; Wi-Fi adds the SSID and
  signal strength.
- Live up/down graphs and transfer totals for the active link. Speeds are
  labelled with explicit per-second units (e.g. `12.3 MiB/s`).
- Established-connection peers grouped by **reverse-DNS hostname** (cached and
  resolved with a short timeout, so the panel never blocks).

## Requirements

- `conky` (built with Xft; ARGB support)
- `lm_sensors` for CPU temperature
- NVIDIA GPUs: `nvidia-smi`
- AMD GPUs: sysfs (`gpu_busy_percent`, `mem_info_vram_*`, hwmon); `radeontop`
  is only used as a fallback
- `otf-font-awesome` / Font Awesome 7 Free for the panel icons
- Fonts: **Fira Sans**, **Noto Sans Mono**
- Network panel: `ip`, `ss`, `nmcli` (NetworkManager), `dig` (dnsutils)

On Arch/CachyOS:

```sh
sudo pacman -S conky lm_sensors otf-font-awesome ttf-fira-sans noto-fonts nvidia-utils
```

On Linux Mint / Debian:

```sh
sudo apt install conky-all lm-sensors fonts-noto-core fonts-noto-mono radeontop dnsutils
./bin/install_fonts.sh
```

`bin/install_fonts.sh` downloads Font Awesome 7.3.1 Free and Fira Sans into
`~/.local/share/fonts` and rebuilds the font cache. No root is needed.

### CPU package power (RAPL)

On Mint/Ubuntu, `/sys/class/powercap/intel-rapl:0/energy_uj` is root-only
(0400), so the CPU power helper prints `N/A` until the permission is relaxed.
The repo ships a udev rule that makes only the RAPL energy counter readable:

```sh
./bin/install_rapl_rule.sh
```

Equivalent manual steps:

```sh
sudo install -Dm644 udev/99-rapl-readable.rules /etc/udev/rules.d/99-rapl-readable.rules
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=powercap
```

Verify with `cat /sys/class/powercap/intel-rapl:0/energy_uj`. This weakens the
RAPL side-channel mitigation, so it is a deliberate personal-machine choice.

## Usage

```sh
./conky_start.sh
```

The script (re)starts both panels and is safe to run repeatedly. The network
panel detects the active interface at runtime, so nothing is rendered per
login. Set `CONKY_IFACE` to override interface detection (it is exported to
the panels).

### Resource use

The expensive probes (process/GPU table, CPU grid) are precomputed by a small
long-lived **sampler** (`bin/conky_sampler.sh`) that writes state files every
few seconds; the panels just read them. This avoids forking a shell per value
on every refresh. On AMD, the shared GPU sampler reads sysfs instead of
spawning `radeontop` for every field.

`conky_start.sh` starts the sampler automatically: as a `systemd --user`
service (`conky-sampler.service`) when systemd is available, otherwise as a
background process. Both panels use only a fraction of a percent of one core.

### Autostart

Add `~/.conky/conky_start.sh` to your autostart entries. On Cinnamon this is
`~/.config/autostart/conky.desktop`; on KDE use *System Settings → Autostart*.
A short startup delay (3–5 s) is recommended so the compositor is ready before
the ARGB panels appear.

> **KDE users — important:** also exclude the panels from session restoration,
> otherwise Plasma relaunches its own copies at login in addition to this
> autostart entry, doubling the panels on every login. In *System Settings →
> Session → Desktop Session → Applications to be excluded from session
> restoration* add `conky` (equivalently: `excludeApps=conky,ConkySystem,ConkyNet`
> under `[General]` in `~/.config/ksmserverrc`).

## Layout

```
conky.conf                 system panel
conky_network.conf         network panel
conky_start.sh             start both panels
bin/                       helper scripts called from the configs
bin/install_fonts.sh       one-time Font Awesome 7 / Fira Sans installer
udev/99-rapl-readable.rules  optional RAPL permission for CPU package power
run/                       runtime lock file (git-ignored)
```

## Notes

- CPU package power is derived from `/sys/class/powercap/intel-rapl:0/energy_uj`
  using a small state file; it prints `N/A` if RAPL is unavailable or not
  readable.
- AMD GPU usage, VRAM, temperature and power are read from sysfs when
  available; `radeontop` is the fallback.
- On Cinnamon/X11 the panels use `own_window_type = 'dock'` plus an ARGB
  visual. On KDE/Wayland the original `normal` window settings are kept.
- Temperature and usage helpers fall back to `N/A` rather than failing.
