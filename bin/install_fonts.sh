#!/usr/bin/env bash
# Install the fonts used by the panels into the user font directory.
# Safe to run repeatedly; it re-downloads the same files.
#
# Requires curl and unzip. No root needed.
set -euo pipefail

DEST="${XDG_DATA_HOME:-$HOME/.local/share}/fonts"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FA_VER="7.3.1"
FA_ZIP="fontawesome-free-${FA_VER}-desktop.zip"
FA_BASE="fontawesome-free-${FA_VER}-desktop/otfs"

mkdir -p "$DEST"

printf 'Downloading Font Awesome %s...\n' "$FA_VER"
curl -fsSL --retry 3 --max-time 120 -o "$TMP/$FA_ZIP" \
    "https://github.com/FortAwesome/Font-Awesome/releases/download/${FA_VER}/${FA_ZIP}"
unzip -o -j "$TMP/$FA_ZIP" \
    "$FA_BASE/Font Awesome 7 Free-Solid-900.otf" \
    "$FA_BASE/Font Awesome 7 Free-Regular-400.otf" \
    -d "$DEST" >/dev/null

printf 'Downloading Fira Sans...\n'
for f in FiraSans-Regular.ttf FiraSans-Bold.ttf FiraSans-Medium.ttf; do
    curl -fsSL --retry 3 --max-time 60 -o "$DEST/$f" \
        "https://raw.githubusercontent.com/google/fonts/main/ofl/firasans/$f"
done

fc-cache -f "$DEST" >/dev/null
printf 'Installed fonts in %s\n' "$DEST"
fc-match 'Fira Sans'
fc-match 'Font Awesome 7 Free'
