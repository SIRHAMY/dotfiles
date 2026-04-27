#!/usr/bin/env bash
# Show output volume %, dim+slash icon when muted. Driven by SketchyBar's
# built-in volume_change event (and system_woke), so no update_freq is set —
# it repaints only when volume actually changes.

set -uo pipefail

NAME="${NAME:-audio}"

COLOR_FG=0xffbcc2cc
COLOR_DIM=0xff5e6570

if ! command -v osascript >/dev/null; then
  sketchybar --set "$NAME" label="VOL --"
  exit 0
fi

vol=$(osascript -e 'output volume of (get volume settings)' 2>/dev/null)
muted=$(osascript -e 'output muted of (get volume settings)' 2>/dev/null)
: "${vol:=0}"

if [[ "$muted" == "true" ]]; then
  sketchybar --set "$NAME" label="VOL MUTE" label.color="$COLOR_DIM"
else
  sketchybar --set "$NAME" label="VOL ${vol}%" label.color="$COLOR_FG"
fi
