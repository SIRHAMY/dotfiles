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

# SF Symbols glyphs as raw UTF-8 (bash 3.2 compatible; see battery.sh).
ICON_WIFI=$'\xf4\x80\x99\x87'      # U+100647 wifi
ICON_WIFI_OFF=$'\xf4\x80\x99\xbd'  # U+10067D wifi.slash

if ! command -v networksetup >/dev/null; then
  sketchybar --set "$NAME" icon="" label="--"
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
  sketchybar --set "$NAME" \
             icon="$ICON_WIFI" \
             icon.color="$COLOR_FG" \
             label="$ssid" \
             label.color="$COLOR_FG"
else
  sketchybar --set "$NAME" \
             icon="$ICON_WIFI_OFF" \
             icon.color="$COLOR_DIM" \
             label="off" \
             label.color="$COLOR_DIM"
fi
