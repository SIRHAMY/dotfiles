#!/usr/bin/env bash
# Update battery item with charge %, charging-aware icon, and threshold colors
# mirroring waybar (warn <30% on battery, crit <15% on battery; charging is
# always normal). Triggered by update_freq=60 and power_source_change.

set -uo pipefail

NAME="${NAME:-battery}"

COLOR_FG=0xffbcc2cc
COLOR_WARN=0xffd19a66
COLOR_CRIT=0xffe06c75
COLOR_OK=0xff10b981

if ! command -v pmset >/dev/null; then
  sketchybar --set "$NAME" label="BAT --"
  exit 0
fi

raw=$(pmset -g batt 2>/dev/null)
pct=$(printf '%s\n' "$raw" | grep -Eo '[0-9]+%' | head -1 | tr -d '%')
source_line=$(printf '%s\n' "$raw" | head -1)
: "${pct:=0}"

charging=0
if [[ "$source_line" == *"'AC Power'"* ]]; then
  charging=1
fi

# Charging is signalled by a leading "+" on the label and the OK (green) color.
# On battery, color alone differentiates normal/warn/crit per waybar thresholds.
if (( charging )); then
  prefix="BAT +"; color="$COLOR_OK"
elif (( pct >= 30 )); then
  prefix="BAT ";  color="$COLOR_FG"
elif (( pct >= 15 )); then
  prefix="BAT ";  color="$COLOR_WARN"
else
  prefix="BAT ";  color="$COLOR_CRIT"
fi

sketchybar --set "$NAME" \
           label="${prefix}${pct}%" \
           label.color="$color"
