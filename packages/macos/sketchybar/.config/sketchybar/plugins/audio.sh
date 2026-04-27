#!/usr/bin/env bash
# Show output volume %, dim+slash icon when muted. Driven by SketchyBar's
# built-in volume_change event (and system_woke), so no update_freq is set —
# it repaints only when volume actually changes.

set -uo pipefail

NAME="${NAME:-audio}"

COLOR_FG=0xffbcc2cc
COLOR_DIM=0xff5e6570

# SF Symbols glyphs as raw UTF-8 (bash 3.2 compatible; see battery.sh).
ICON_VOL_3=$'\xf4\x80\x8a\xa0'  # U+1002A0 speaker.wave.3
ICON_VOL_2=$'\xf4\x80\x8a\x9f'  # U+10029F speaker.wave.2
ICON_VOL_1=$'\xf4\x80\x8a\x9e'  # U+10029E speaker.wave.1
ICON_MUTE=$'\xf4\x80\x8a\x9c'   # U+10029C speaker.slash

if ! command -v osascript >/dev/null; then
  sketchybar --set "$NAME" icon="" label="--"
  exit 0
fi

vol=$(osascript -e 'output volume of (get volume settings)' 2>/dev/null)
muted=$(osascript -e 'output muted of (get volume settings)' 2>/dev/null)
: "${vol:=0}"

if [[ "$muted" == "true" ]]; then
  sketchybar --set "$NAME" \
             icon="$ICON_MUTE" \
             icon.color="$COLOR_DIM" \
             label="MUTE" \
             label.color="$COLOR_DIM"
  exit 0
fi

if   (( vol >= 66 )); then icon="$ICON_VOL_3"
elif (( vol >= 33 )); then icon="$ICON_VOL_2"
else                       icon="$ICON_VOL_1"
fi

sketchybar --set "$NAME" \
           icon="$icon" \
           icon.color="$COLOR_FG" \
           label="${vol}%" \
           label.color="$COLOR_FG"
