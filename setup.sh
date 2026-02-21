#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$HOME/.config"

link() {
    local src="$DOTFILES/$1"
    local dst="$CONFIG/$2"

    mkdir -p "$(dirname "$dst")"

    if [ -L "$dst" ]; then
        rm "$dst"
    elif [ -e "$dst" ]; then
        echo "Backing up existing $dst -> ${dst}.bak"
        mv "$dst" "${dst}.bak"
    fi

    ln -s "$src" "$dst"
    echo "Linked $dst -> $src"
}

link "sway/config"                  "sway/config"
link "waybar/config.jsonc"          "waybar/config.jsonc"
link "waybar/style.css"             "waybar/style.css"
link "mako/config"                  "mako/config"
link "ghostty/config"               "ghostty/config"
link "ghostty/themes/terminal-garden" "ghostty/themes/terminal-garden"

echo "Done! Reload sway with \$mod+Shift+c to pick up any changes."
