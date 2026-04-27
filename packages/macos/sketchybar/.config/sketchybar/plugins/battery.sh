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

# SF Symbols glyphs as raw UTF-8 byte sequences (works on macOS bash 3.2,
# which doesn't support $'\Uxxxxxxxx'). All SF Symbols private-use codepoints
# live in U+10**** and encode to F4 80 XX XX. Verify in SF Symbols.app
# (Edit > Copy Unicode value) if a glyph doesn't render.
ICON_BAT_100=$'\xf4\x80\x9b\xaa'   # U+1006EA battery.100
ICON_BAT_75=$'\xf4\x80\x9b\xa9'    # U+1006E9 battery.75
ICON_BAT_50=$'\xf4\x80\x9b\xa8'    # U+1006E8 battery.50
ICON_BAT_25=$'\xf4\x80\x9b\xa7'    # U+1006E7 battery.25
ICON_BAT_0=$'\xf4\x80\x9b\xa6'     # U+1006E6 battery.0
ICON_CHARGING=$'\xf4\x80\x9b\xae'  # U+1006EE battery.100.bolt

if ! command -v pmset >/dev/null; then
  sketchybar --set "$NAME" icon="" label="--"
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

if (( charging )); then
  icon="$ICON_CHARGING"
  color="$COLOR_OK"
elif (( pct >= 88 )); then
  icon="$ICON_BAT_100"; color="$COLOR_FG"
elif (( pct >= 63 )); then
  icon="$ICON_BAT_75";  color="$COLOR_FG"
elif (( pct >= 38 )); then
  icon="$ICON_BAT_50";  color="$COLOR_FG"
elif (( pct >= 30 )); then
  icon="$ICON_BAT_25";  color="$COLOR_FG"
elif (( pct >= 15 )); then
  icon="$ICON_BAT_25";  color="$COLOR_WARN"
else
  icon="$ICON_BAT_0";   color="$COLOR_CRIT"
fi

sketchybar --set "$NAME" \
           icon="$icon" \
           icon.color="$color" \
           label="${pct}%" \
           label.color="$color"
