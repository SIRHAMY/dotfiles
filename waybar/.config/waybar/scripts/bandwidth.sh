#!/bin/bash
# Fixed-width bandwidth monitor for waybar
# Outputs kB/s with consistent formatting to prevent bar fluctuation

CACHE="/tmp/waybar-bandwidth"

IFACE=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'dev \K\S+')

if [ -z "$IFACE" ]; then
    printf '{"text": "\u2191 --- kB \u2193 --- kB", "class": "disconnected"}\n'
    exit 0
fi

RX=$(cat /sys/class/net/"$IFACE"/statistics/rx_bytes 2>/dev/null || echo 0)
TX=$(cat /sys/class/net/"$IFACE"/statistics/tx_bytes 2>/dev/null || echo 0)
NOW=$(date +%s)

if [ -f "$CACHE" ]; then
    read -r PREV_RX PREV_TX PREV_TIME < "$CACHE"
    ELAPSED=$((NOW - PREV_TIME))
    if [ "$ELAPSED" -gt 0 ]; then
        RX_KB=$(( (RX - PREV_RX) / 1024 / ELAPSED ))
        TX_KB=$(( (TX - PREV_TX) / 1024 / ELAPSED ))
    else
        RX_KB=0
        TX_KB=0
    fi
else
    RX_KB=0
    TX_KB=0
fi

echo "$RX $TX $NOW" > "$CACHE"
printf '{"text": "\u2191%4d kB \u2193%4d kB"}\n' "$TX_KB" "$RX_KB"
