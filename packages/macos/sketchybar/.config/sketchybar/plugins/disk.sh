#!/usr/bin/env bash
# Show root filesystem used % from `df /`. Triggered by update_freq=60.

set -uo pipefail

NAME="${NAME:-disk}"

COLOR_FG=0xffbcc2cc
COLOR_WARN=0xffd19a66
COLOR_CRIT=0xffe06c75

if ! command -v df >/dev/null; then
  sketchybar --set "$NAME" label="DISK --"
  exit 0
fi

pct=$(df / 2>/dev/null | awk 'END {gsub("%","",$5); print $5}')
: "${pct:=0}"

if   (( pct >= 90 )); then color="$COLOR_CRIT"
elif (( pct >= 70 )); then color="$COLOR_WARN"
else                       color="$COLOR_FG"
fi

sketchybar --set "$NAME" label="DISK ${pct}%" label.color="$color"
