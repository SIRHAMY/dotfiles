#!/bin/bash
# Caffeine toggle for waybar
#   off: normal swayidle behavior (lock + screen off, lid-close suspends)
#   on:  inhibits idle, sleep, and lid-switch — bag-safe, nothing fires

STATEFILE="/tmp/waybar-caffeine.state"
PIDFILE="/tmp/waybar-caffeine.pid"

read_state() {
    [ -f "$STATEFILE" ] && cat "$STATEFILE" || echo "off"
}

kill_inhibitor() {
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        kill "$(cat "$PIDFILE")"
    fi
    rm -f "$PIDFILE"
}

start_inhibitor() {
    local what="$1"
    systemd-inhibit --what="$what" --who=caffeine --why="User requested" sleep infinity &
    echo $! > "$PIDFILE"
}

apply_state() {
    kill_inhibitor
    case "$1" in
        on) start_inhibitor "idle:sleep:handle-lid-switch" ;;
    esac
    echo "$1" > "$STATEFILE"
}

toggle() {
    case "$(read_state)" in
        off) apply_state "on" ;;
        *)   apply_state "off" ;;
    esac
}

# Reconcile: if the inhibitor died, fall back to off
status() {
    local state
    state="$(read_state)"
    if [ "$state" != "off" ]; then
        if ! { [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; }; then
            state="off"
            echo "$state" > "$STATEFILE"
            rm -f "$PIDFILE"
        fi
    fi

    case "$state" in
        on)
            printf '{"text": "<span font='\''Font Awesome 6 Free Solid'\''>&#xf06e;</span>", "tooltip": "Caffeine: ON — no sleep, no lock", "class": "on"}\n'
            ;;
        *)
            printf '{"text": "<span font='\''Font Awesome 6 Free Solid'\''>&#xf070;</span>", "tooltip": "Caffeine: OFF — normal sleep and lock", "class": "off"}\n'
            ;;
    esac
}

case "$1" in
    toggle) toggle ;;
    *) status ;;
esac
