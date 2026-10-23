#!/usr/bin/env bash
# Install the udev rule that makes the RAPL package energy counter readable
# by the conky CPU-power helper. Requires root (sudo).
set -euo pipefail

DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
RULE="$DIR/udev/99-rapl-readable.rules"
DEST="/etc/udev/rules.d/99-rapl-readable.rules"

sudo install -Dm644 "$RULE" "$DEST"
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=powercap

printf 'Installed %s\n' "$DEST"
printf 'energy_uj: '
cat /sys/class/powercap/intel-rapl:0/energy_uj
