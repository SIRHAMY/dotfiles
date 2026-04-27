os := `uname -s`

packages_common := "zsh tmux ghostty zellij nvim yazi git bash bin"
packages_linux  := "zsh-linux bin-linux sway swaylock waybar mako wofi fontconfig environment.d"
packages_macos  := "zsh-macos aerospace"

# Link everything for the current OS. Pre-flights conflicts (fails loud on any
# pre-existing non-symlink at a target path), then stows per bucket.
all:
    @just check-conflicts
    @just _stow-bucket common {{packages_common}}
    @if [ "{{os}}" = "Linux" ]; then just _stow-bucket linux {{packages_linux}}; fi
    @if [ "{{os}}" = "Darwin" ] && [ -n "{{packages_macos}}" ]; then just _stow-bucket macos {{packages_macos}}; fi
    @echo "Done. Run 'just reload' on Linux to reload sway/waybar."

# Unlink everything (reversibility — PRD NFR). Three-bucket form: OS bucket
# unwinds first so any OS-specific directory guards get cleaned up before the
# common owner.
unstow-all:
    @if [ "{{os}}" = "Linux" ]; then just _unstow-bucket linux {{packages_linux}}; fi
    @if [ "{{os}}" = "Darwin" ] && [ -n "{{packages_macos}}" ]; then just _unstow-bucket macos {{packages_macos}}; fi
    @just _unstow-bucket common {{packages_common}}
    @echo "Done. Packages unlinked. Per-OS system state (Caps->Esc etc.) not reverted."

# Restow — useful after deleting a snippet file to clean up dangling symlinks.
restow:
    @just _stow-bucket-flag -R common {{packages_common}}
    @if [ "{{os}}" = "Linux" ]; then just _stow-bucket-flag -R linux {{packages_linux}}; fi
    @if [ "{{os}}" = "Darwin" ] && [ -n "{{packages_macos}}" ]; then just _stow-bucket-flag -R macos {{packages_macos}}; fi

# Dry-run plan for the current OS.
plan:
    @just _plan-bucket common {{packages_common}}
    @if [ "{{os}}" = "Linux" ]; then just _plan-bucket linux {{packages_linux}}; fi
    @if [ "{{os}}" = "Darwin" ] && [ -n "{{packages_macos}}" ]; then just _plan-bucket macos {{packages_macos}}; fi

# Pre-flight: walk the package tree directly (no stow-output parsing). For every
# file a package would link to $HOME, if the target exists as a non-symlink or
# as a symlink pointing outside this repo, fail loudly listing all conflicts and
# a suggested remediation. This satisfies PRD Must-Have "Pre-existing dotfile
# handling — exit non-zero with a clear remediation message."
#
# Not marked [private] so users can run `just check-conflicts` standalone for
# pre-migration auditing.
check-conflicts:
    #!/usr/bin/env bash
    set -euo pipefail
    repo_root="$(git rev-parse --show-toplevel)"
    case "{{os}}" in
      Linux)  buckets=(common linux) ;;
      Darwin) buckets=(common macos) ;;
      *)      echo "Unsupported OS: {{os}}" >&2; exit 2 ;;
    esac
    conflicts=()
    for b in "${buckets[@]}"; do
      for pkg in "$repo_root/packages/$b"/*/; do
        [ -d "$pkg" ] || continue
        # Walk every regular file and symlink under the package.
        while IFS= read -r -d '' src; do
          rel="${src#"$pkg"}"       # path relative to the package root
          abs="$HOME/$rel"          # where stow would link it
          if [ -L "$abs" ]; then
            # Existing symlink — OK iff it points into our repo.
            lnk="$(readlink "$abs")"
            case "$lnk" in
              "$repo_root"/*|./*|../*) : ;;   # ours (or relative to stow)
              /*) conflicts+=("$abs -> $lnk (foreign symlink)") ;;
              *)  : ;;
            esac
          elif [ -e "$abs" ]; then
            conflicts+=("$abs (non-symlink; would collide)")
          fi
        done < <(find "$pkg" -mindepth 1 \( -type f -o -type l \) -print0)
      done
    done
    if [ "${#conflicts[@]}" -gt 0 ]; then
      echo "check-conflicts: pre-existing paths would collide with stow:" >&2
      printf '  %s\n' "${conflicts[@]}" >&2
      cat >&2 <<'EOF'

    To resolve: back up each conflicting file and rerun. For example:
      mv ~/.zshrc ~/.zshrc.pre-stow.bak
    Then: just setup
    EOF
      exit 1
    fi

# Setup on a fresh machine (install deps + link everything)
setup:
    @echo "Setting up for {{os}}..."
    @just install-deps
    @just all
    @if [ "{{os}}" = "Linux" ]; then just setup-sway-session; fi

[private]
_stow-bucket bucket *pkgs:
    #!/usr/bin/env bash
    set -euo pipefail
    for pkg in {{pkgs}}; do
      echo "Stowing $pkg from packages/{{bucket}}..."
      stow --no-folding -d packages/{{bucket}} -t ~ "$pkg"
    done

[private]
_unstow-bucket bucket *pkgs:
    #!/usr/bin/env bash
    set -euo pipefail
    for pkg in {{pkgs}}; do
      echo "Unstowing $pkg from packages/{{bucket}}..."
      stow -D -d packages/{{bucket}} -t ~ "$pkg" || true
    done

[private]
_stow-bucket-flag flag bucket *pkgs:
    #!/usr/bin/env bash
    set -euo pipefail
    for pkg in {{pkgs}}; do
      stow {{flag}} --no-folding -d packages/{{bucket}} -t ~ "$pkg"
    done

[private]
_plan-bucket bucket *pkgs:
    #!/usr/bin/env bash
    for pkg in {{pkgs}}; do
      echo "=== $pkg ==="
      stow -n -v --no-folding -d packages/{{bucket}} -t ~ "$pkg" 2>&1
    done

# Install dependencies for the current OS
[private]
install-deps:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{os}}" = "Linux" ]; then
        # Enable COPR repos for packages not in default Fedora repos
        sudo dnf copr enable atim/lazygit -y
        deps=(stow zsh zoxide fzf tmux neovim fd-find lazygit sway swaylock swayidle waybar mako wofi \
              grim slurp wl-clipboard brightnessctl playerctl \
              zsh-autosuggestions zsh-syntax-highlighting \
              ibm-plex-sans-fonts ibm-plex-mono-fonts \
              NetworkManager-tui gnome-keyring flatpak)
        echo "Installing with dnf: ${deps[*]}"
        sudo dnf install -y "${deps[@]}"
        just install-zellij
        just install-yazi
        just install-resvg
        just install-flatpaks
    elif [ "{{os}}" = "Darwin" ]; then
        if ! command -v brew >/dev/null; then
            echo "Homebrew not found. Install from https://brew.sh" >&2
            exit 1
        fi
        brew install stow zsh zoxide fzf zellij tmux neovim fd lazygit yazi \
            zsh-autosuggestions zsh-syntax-highlighting
        # Cask installs are guarded for idempotency: brew --cask install errors
        # on already-installed in some versions. AeroSpace is in a third-party
        # tap (nikitabobko/tap), so install with the fully-qualified name; the
        # short name still works for the `brew list` idempotency probe.
        brew list --cask ghostty &>/dev/null || brew install --cask ghostty
        brew list --cask aerospace &>/dev/null || brew install --cask nikitabobko/tap/aerospace
    else
        echo "Unsupported OS: {{os}}" >&2
        exit 1
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

# Install yazi from prebuilt binary
[private]
install-yazi:
    #!/usr/bin/env bash
    set -euo pipefail
    if command -v yazi >/dev/null; then
        echo "yazi already installed, skipping."
        exit 0
    fi
    echo "Installing yazi from GitHub release..."
    local_bin="$HOME/.local/bin"
    mkdir -p "$local_bin"
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT
    arch=$(uname -m)
    url="https://github.com/sxyazi/yazi/releases/latest/download/yazi-${arch}-unknown-linux-musl.zip"
    echo "Downloading $url"
    curl -fsSL "$url" -o "$tmpdir/yazi.zip"
    unzip -o "$tmpdir/yazi.zip" -d "$tmpdir"
    install -m 755 "$tmpdir/yazi-${arch}-unknown-linux-musl/yazi" "$local_bin/yazi"
    install -m 755 "$tmpdir/yazi-${arch}-unknown-linux-musl/ya" "$local_bin/ya"
    echo "yazi installed to $local_bin/yazi"

# Install resvg from prebuilt binary (SVG renderer, used by yazi for previews)
[private]
install-resvg:
    #!/usr/bin/env bash
    set -euo pipefail
    if command -v resvg >/dev/null; then
        echo "resvg already installed, skipping."
        exit 0
    fi
    echo "Installing resvg from GitHub release..."
    local_bin="$HOME/.local/bin"
    mkdir -p "$local_bin"
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT
    url="https://github.com/linebender/resvg/releases/latest/download/resvg-linux-x86_64.tar.gz"
    echo "Downloading $url"
    curl -fsSL "$url" | tar -xz -C "$tmpdir"
    install -m 755 "$tmpdir/resvg" "$local_bin/resvg"
    echo "resvg installed to $local_bin/resvg"

# Install flatpak apps
[private]
install-flatpaks:
    #!/usr/bin/env bash
    set -euo pipefail
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    flatpak install -y flathub md.obsidian.Obsidian
    flatpak override --user --socket=wayland md.obsidian.Obsidian
    echo "Flatpak apps installed."

# Install sway session entry (auto-detects NVIDIA at login time)
setup-sway-session:
    #!/usr/bin/env bash
    set -euo pipefail

    # Install sway-launch to a system-wide path so the display manager can find it
    sudo install -m 755 packages/linux/bin-linux/.local/bin/sway-launch /usr/local/bin/sway-launch
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
    if [ "{{os}}" = "Linux" ]; then
        pgrep waybar >/dev/null && killall -SIGUSR2 waybar && echo "Reloaded waybar" || true
        pgrep mako >/dev/null && makoctl reload && echo "Reloaded mako" || true
        pgrep sway >/dev/null && swaymsg reload >/dev/null && echo "Reloaded sway" || true
    fi
    echo "Done!"
