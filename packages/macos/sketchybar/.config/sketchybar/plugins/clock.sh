#!/usr/bin/env bash
# Update SketchyBar clock label to current HH:MM. Triggered by update_freq=30
# and on system_woke.

set -uo pipefail

NAME="${NAME:-clock}"

sketchybar --set "$NAME" label="$(date '+%H:%M')"
