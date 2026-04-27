#!/usr/bin/env bash
# Show root filesystem used % from `df /`. Triggered by update_freq=60.

set -uo pipefail

NAME="${NAME:-disk}"

COLOR_FG=0xffbcc2cc
COLOR_WARN=0xffd19a66
COLOR_CRIT=0xffe06c75

# SF Symbols glyph as raw UTF-8 (bash 3.2 compatible; see battery.sh).
ICON_DISK=$'\xf4\x80\xaa\x97'  # U+100A97 internaldrive

if ! command -v df >/dev/null; then
  sketchybar --set "$NAME" icon="" label="--"
  exit 0
fi

pct=$(df / 2>/dev/null | awk 'END {gsub("%","",$5); print $5}')
: "${pct:=0}"

if   (( pct >= 90 )); then color="$COLOR_CRIT"
elif (( pct >= 70 )); then color="$COLOR_WARN"
else                       color="$COLOR_FG"
fi

sketchybar --set "$NAME" \
           icon="$ICON_DISK" \
           icon.color="$color" \
           label="${pct}%" \
           label.color="$color"
