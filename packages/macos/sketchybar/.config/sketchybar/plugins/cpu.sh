#!/usr/bin/env bash
# CPU usage % as user+sys from `top -l 1 -n 0`. Single-sample top reports
# instantaneous values relative to the previous tick; that's fine for a 5s
# refresh and avoids the ~1s delay of `top -l 2`. Color thresholds mirror
# waybar (warn 60, crit 90).

set -uo pipefail

NAME="${NAME:-cpu}"

COLOR_FG=0xffbcc2cc
COLOR_WARN=0xffd19a66
COLOR_CRIT=0xffe06c75

# SF Symbols glyph as raw UTF-8 (bash 3.2 compatible; see battery.sh).
ICON_CPU=$'\xf4\x80\xab\xa6'  # U+100AE6 cpu

if ! command -v top >/dev/null; then
  sketchybar --set "$NAME" icon="" label="--"
  exit 0
fi

# Output line: "CPU usage: 5.55% user, 2.22% sys, 92.21% idle"
pct=$(top -l 1 -n 0 2>/dev/null \
      | awk '/CPU usage/ {gsub("%",""); printf "%d\n", $3 + $5; exit}')
: "${pct:=0}"

if   (( pct >= 90 )); then color="$COLOR_CRIT"
elif (( pct >= 60 )); then color="$COLOR_WARN"
else                       color="$COLOR_FG"
fi

sketchybar --set "$NAME" \
           icon="$ICON_CPU" \
           icon.color="$color" \
           label="${pct}%" \
           label.color="$color"
