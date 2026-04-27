#!/usr/bin/env bash
# Update SketchyBar workspace pills based on current AeroSpace state. Called
# from the ws.controller item on aerospace_workspace_change and display_change.
# Strategy: hide every declared space.M.W item, then enable + color the ones
# AeroSpace reports as non-empty per monitor; highlight the focused one.

set -uo pipefail

COLOR_FG=0xffbcc2cc
COLOR_ACTIVE_BG=0xff10b981
COLOR_ACTIVE_FG=0xff161616
COLOR_TRANSPARENT=0x00000000

focused_ws=$(aerospace list-workspaces --focused 2>/dev/null | tr -d '[:space:]')

args=()

for monitor in 1 2 3; do
  for ws in $(seq 1 20); do
    args+=(--set "space.$monitor.$ws" drawing=off)
  done

  ws_list=$(aerospace list-workspaces --monitor "$monitor" --empty no 2>/dev/null) || continue

  while IFS= read -r ws; do
    ws=$(printf '%s' "$ws" | tr -d '[:space:]')
    [[ -z "$ws" ]] && continue
    if [[ "$ws" == "$focused_ws" ]]; then
      args+=(--set "space.$monitor.$ws" \
             drawing=on \
             background.color=$COLOR_ACTIVE_BG \
             label.color=$COLOR_ACTIVE_FG)
    else
      args+=(--set "space.$monitor.$ws" \
             drawing=on \
             background.color=$COLOR_TRANSPARENT \
             label.color=$COLOR_FG)
    fi
  done <<< "$ws_list"
done

sketchybar "${args[@]}"
