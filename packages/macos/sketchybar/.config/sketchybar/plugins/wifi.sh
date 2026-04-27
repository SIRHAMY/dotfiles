#!/usr/bin/env bash
# Show wifi SSID (or "off") and dim color when disconnected. Wifi interface is
# detected dynamically (en0 on most Macs, en1 on some). Signal strength is
# omitted: macOS Sonoma+ removed the `airport -I` CLI and the alternatives
# require sudo; SSID alone is enough for "am I connected?". Triggered by
# update_freq=60 and system_woke.

set -uo pipefail

NAME="${NAME:-wifi}"

COLOR_FG=0xffbcc2cc
COLOR_DIM=0xff5e6570

if ! command -v networksetup >/dev/null; then
  sketchybar --set "$NAME" label="WIFI --"
  exit 0
fi

iface=$(networksetup -listallhardwareports 2>/dev/null \
        | awk '/Hardware Port: Wi-Fi/ {getline; print $2; exit}')

ssid=""
if [[ -n "$iface" ]]; then
  ssid=$(networksetup -getairportnetwork "$iface" 2>/dev/null \
         | sed -n 's/^Current Wi-Fi Network: //p')
fi

if [[ -n "$ssid" ]]; then
  sketchybar --set "$NAME" label="WIFI $ssid" label.color="$COLOR_FG"
else
  sketchybar --set "$NAME" label="WIFI off"   label.color="$COLOR_DIM"
fi
