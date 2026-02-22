#!/bin/sh
num=$(swaymsg -t get_workspaces | jq -r '.[] | select(.focused) | .num')
name=$(wofi --dmenu -p "Rename workspace")
if [ -n "$name" ]; then
    swaymsg "rename workspace to \"$num($name)\""
fi
