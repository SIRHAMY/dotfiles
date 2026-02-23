os := `uname -s`

packages_common := "zsh tmux git bash ghostty zellij bin nvim"
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
    @if [ "{{os}}" = "Linux" ]; then just setup-sway-session; fi

# Install dependencies for the current OS
[private]
install-deps:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ "{{os}}" == "Darwin" ]]; then
        command -v brew >/dev/null || { echo "Homebrew not found. Install from https://brew.sh"; exit 1; }
        deps=(stow zsh zoxide fzf ghostty zellij tmux neovim fd lazygit)
        echo "Installing with brew: ${deps[*]}"
        brew install "${deps[@]}"
    else
        # Enable COPR repos for packages not in default Fedora repos
        sudo dnf copr enable atim/lazygit -y
        deps=(stow zsh zoxide fzf tmux neovim fd-find lazygit sway swaylock swayidle waybar mako wofi \
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

# Install sway session entry (auto-detects NVIDIA at login time)
setup-sway-session:
    #!/usr/bin/env bash
    set -euo pipefail

    # Install sway-launch to a system-wide path so the display manager can find it
    sudo install -m 755 bin/.local/bin/sway-launch /usr/local/bin/sway-launch
    echo "Installed /usr/local/bin/sway-launch"

    # Add a login session entry that uses sway-launch
    printf '%s\n' \
        '[Desktop Entry]' \
        'Name=Sway (Custom)' \
        'Comment=Sway via sway-launch (auto-detects NVIDIA)' \
        'Exec=/usr/local/bin/sway-launch' \
        'Type=Application' \
        'DesktopNames=sway;wlroots' \
        | sudo tee /usr/share/wayland-sessions/sway-custom.desktop > /dev/null
    echo "Installed /usr/share/wayland-sessions/sway-custom.desktop"

    # Remove the old nvidia-only session entry if present
    if [[ -f /usr/share/wayland-sessions/sway-nvidia.desktop ]]; then
        sudo rm /usr/share/wayland-sessions/sway-nvidia.desktop
        echo "Removed old sway-nvidia.desktop"
    fi

    # NVIDIA-specific kernel configuration
    if lspci | grep -qi nvidia; then
        echo "NVIDIA GPU detected. Installing kernel compatibility..."

        # Enable DRM kernel modesetting (required for Wayland)
        echo 'options nvidia_drm modeset=1 fbdev=1' | sudo tee /etc/modprobe.d/nvidia-drm.conf
        echo "Installed /etc/modprobe.d/nvidia-drm.conf"

        # Add nvidia_drm.modeset=1 to kernel cmdline if not already present
        if ! grep -q 'nvidia_drm.modeset=1' /etc/default/grub; then
            sudo sed -i 's/GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="\1 nvidia_drm.modeset=1 nvidia_drm.fbdev=1"/' /etc/default/grub
            sudo grub2-mkconfig -o /boot/grub2/grub.cfg
            echo "Updated GRUB cmdline. A reboot is required for kernel params to take effect."
        else
            echo "GRUB cmdline already has nvidia_drm.modeset=1"
        fi
    else
        echo "No NVIDIA GPU detected, skipping kernel config."
    fi

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
