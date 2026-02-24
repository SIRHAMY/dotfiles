#!/bin/bash
# Caffeine toggle for waybar - prevents system idle/sleep

PIDFILE="/tmp/waybar-caffeine.pid"

toggle() {
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        kill "$(cat "$PIDFILE")"
        rm -f "$PIDFILE"
    else
        systemd-inhibit --what=idle --who=caffeine --why="User requested" sleep infinity &
        echo $! > "$PIDFILE"
    fi
}

status() {
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        printf '{"text": "<span font='\''Font Awesome 6 Free Solid'\''>&#xf06e;</span>", "tooltip": "Caffeine: ON (click to sleep)", "class": "on"}\n'
    else
        printf '{"text": "<span font='\''Font Awesome 6 Free Solid'\''>&#xf070;</span>", "tooltip": "Caffeine: OFF (click to stay awake)", "class": "off"}\n'
    fi
}

case "$1" in
    toggle) toggle ;;
    *) status ;;
esac
