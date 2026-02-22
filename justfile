os := `uname -s`

packages_common := "zsh tmux git bash ghostty zellij bin"
packages_linux  := "sway swaylock waybar mako environment.d"

packages := if os == "Darwin" { packages_common } else { packages_common + " " + packages_linux }

# Link all packages
all:
    @for pkg in {{packages}}; do \
        echo "Stowing $pkg..."; \
        stow -t ~ $pkg; \
    done
    @echo "Done! All packages linked."
    @just reload

# Link a single package
stow package:
    stow -t ~ {{package}}

# Unlink a single package
unstow package:
    stow -D -t ~ {{package}}

# Unlink all packages
unstow-all:
    @for pkg in {{packages}}; do \
        echo "Unstowing $pkg..."; \
        stow -D -t ~ $pkg; \
    done
    @echo "Done! All packages unlinked."

# Show what would be linked (dry run)
plan:
    @for pkg in {{packages}}; do \
        echo "=== $pkg ==="; \
        stow -n -v -t ~ $pkg 2>&1; \
    done

# Setup on a fresh machine (install deps + link everything)
setup:
    @echo "Setting up for {{os}}..."
    @just install-deps
    @just all

# Install dependencies for the current OS
[private]
install-deps:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ "{{os}}" == "Darwin" ]]; then
        command -v brew >/dev/null || { echo "Homebrew not found. Install from https://brew.sh"; exit 1; }
        deps=(stow zsh zoxide fzf ghostty zellij tmux)
        echo "Installing with brew: ${deps[*]}"
        brew install "${deps[@]}"
    else
        deps=(stow zsh zoxide fzf tmux sway swaylock swayidle waybar mako wofi \
              grim slurp wl-clipboard brightnessctl playerctl \
              zsh-autosuggestions zsh-syntax-highlighting)
        echo "Installing with dnf: ${deps[*]}"
        sudo dnf install -y "${deps[@]}"
        just install-zellij
    fi

# Install zellij from prebuilt binary
[private]
install-zellij:
    #!/usr/bin/env bash
    set -euo pipefail
    if command -v zellij >/dev/null; then
        echo "zellij already installed, skipping."
        exit 0
    fi
    echo "Installing zellij from GitHub release..."
    local_bin="$HOME/.local/bin"
    mkdir -p "$local_bin"
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT
    arch=$(uname -m)
    url="https://github.com/zellij-org/zellij/releases/latest/download/zellij-${arch}-unknown-linux-musl.tar.gz"
    echo "Downloading $url"
    curl -fsSL "$url" | tar -xz -C "$tmpdir"
    install -m 755 "$tmpdir/zellij" "$local_bin/zellij"
    echo "zellij installed to $local_bin/zellij"

# Reload running apps to pick up config changes
reload:
    #!/usr/bin/env bash
    echo "Reloading apps..."
    if [[ "{{os}}" == "Linux" ]]; then
        pgrep waybar >/dev/null && killall -SIGUSR2 waybar && echo "Reloaded waybar" || true
        pgrep mako >/dev/null && makoctl reload && echo "Reloaded mako" || true
        pgrep sway >/dev/null && swaymsg reload >/dev/null && echo "Reloaded sway" || true
    fi
    echo "Done!"
