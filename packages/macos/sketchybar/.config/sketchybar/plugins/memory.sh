#!/usr/bin/env bash
# Memory used % from vm_stat: (active + wired + compressed) * page_size / total.
# This matches Activity Monitor's "Memory Used" closer than `memory_pressure`'s
# free-pct readout, and avoids memory_pressure's multi-second sampling delay.
# Triggered by update_freq=10. Color thresholds mirror waybar (warn 70, crit 90).

set -uo pipefail

NAME="${NAME:-memory}"

COLOR_FG=0xffbcc2cc
COLOR_WARN=0xffd19a66
COLOR_CRIT=0xffe06c75

# SF Symbols glyph as raw UTF-8 (bash 3.2 compatible; see battery.sh).
ICON_MEM=$'\xf4\x80\xab\xa8'  # U+100AE8 memorychip

if ! command -v vm_stat >/dev/null || ! command -v sysctl >/dev/null; then
  sketchybar --set "$NAME" icon="" label="--"
  exit 0
fi

total=$(sysctl -n hw.memsize 2>/dev/null)
vmstat_out=$(vm_stat 2>/dev/null)
ps=$(printf '%s\n' "$vmstat_out" | sed -n 's/.*page size of \([0-9]*\) bytes.*/\1/p')

if [[ -z "$total" || -z "$ps" ]]; then
  sketchybar --set "$NAME" icon="$ICON_MEM" label="--"
  exit 0
fi

read_pages() {
  printf '%s\n' "$vmstat_out" | awk -v k="$1" '$0 ~ k {gsub("\\.",""); print $NF; exit}'
}
active=$(read_pages "Pages active")
wired=$(read_pages "Pages wired down")
compressed=$(read_pages "Pages occupied by compressor")
: "${active:=0}" "${wired:=0}" "${compressed:=0}"

used=$(( (active + wired + compressed) * ps ))
pct=$(( used * 100 / total ))

if   (( pct >= 90 )); then color="$COLOR_CRIT"
elif (( pct >= 70 )); then color="$COLOR_WARN"
else                       color="$COLOR_FG"
fi

sketchybar --set "$NAME" \
           icon="$ICON_MEM" \
           icon.color="$color" \
           label="${pct}%" \
           label.color="$color"
