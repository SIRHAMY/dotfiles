os := `uname -s`

# Profile-aware package classification (WRK-002). Profile-aware recipes
# (`setup`, `all`, `check-conflicts`, `unstow-all`, `restow`, `plan`) all
# resolve a profile via `_profile-context` and pick from these vars.
packages_common_cli         := "zsh tmux zellij nvim yazi git bash bin"
packages_common_workstation := "ghostty"
packages_linux_workstation  := "zsh-linux bin-linux sway swaylock waybar mako wofi fontconfig environment.d"
packages_linux_remote       := "zsh-linux"
packages_macos_workstation  := "zsh-macos aerospace sketchybar"

# Link everything for the resolved profile. Pre-flights conflicts (fails loud
# on any pre-existing non-symlink at a target path), then stows per bucket.
all profile="":
    #!/usr/bin/env bash
    set -euo pipefail
    ctx="$(just _profile-context "{{profile}}")"
    eval "$ctx"
    just check-conflicts profile="$profile"
    just _stow-bucket common $common_pkgs
    if [ -n "$os_pkgs" ]; then
      just _stow-bucket "$os_bucket" $os_pkgs
    fi
    echo "Done. Run 'just reload' on Linux to reload sway/waybar."

# Unlink everything (reversibility — PRD NFR). OS bucket unwinds first so any
# OS-specific directory guards get cleaned up before the common owner.
unstow-all profile="":
    #!/usr/bin/env bash
    set -euo pipefail
    ctx="$(just _profile-context "{{profile}}")"
    eval "$ctx"
    if [ -n "$os_pkgs" ]; then
      just _unstow-bucket "$os_bucket" $os_pkgs
    fi
    just _unstow-bucket common $common_pkgs
    echo "Done. Packages unlinked. Per-OS system state (Caps->Esc etc.) not reverted."

# Restow — useful after deleting a snippet file to clean up dangling symlinks.
restow profile="":
    #!/usr/bin/env bash
    set -euo pipefail
    ctx="$(just _profile-context "{{profile}}")"
    eval "$ctx"
    just _stow-bucket-flag -R common $common_pkgs
    if [ -n "$os_pkgs" ]; then
      just _stow-bucket-flag -R "$os_bucket" $os_pkgs
    fi

# Dry-run plan for the resolved profile.
plan profile="":
    #!/usr/bin/env bash
    set -euo pipefail
    ctx="$(just _profile-context "{{profile}}")"
    eval "$ctx"
    just _plan-bucket common $common_pkgs
    if [ -n "$os_pkgs" ]; then
      just _plan-bucket "$os_bucket" $os_pkgs
    fi

# Pre-flight: walk the resolved profile's package list (no stow-output parsing).
# For every file a package would link to $HOME, if the target exists as a
# non-symlink or as a symlink pointing outside this repo, fail loudly listing
# all conflicts and a suggested remediation. This satisfies PRD Must-Have
# "Pre-existing dotfile handling — exit non-zero with a clear remediation
# message."
#
# Profile-aware (WRK-002 P4): walks only directories named in the resolved
# profile's package list, not every directory in the bucket. Avoids false-fail
# on stale workstation symlinks during a remote install.
#
# Not marked [private] so users can run `just check-conflicts profile=<name>`
# standalone for pre-migration auditing.
check-conflicts profile="":
    #!/usr/bin/env bash
    set -euo pipefail
    ctx="$(just _profile-context "{{profile}}")"
    eval "$ctx"
    repo_root="$(git rev-parse --show-toplevel)"
    pkg_paths=()
    for p in $common_pkgs; do pkg_paths+=("$repo_root/packages/common/$p"); done
    for p in $os_pkgs;     do pkg_paths+=("$repo_root/packages/$os_bucket/$p"); done
    conflicts=()
    for pkg in "${pkg_paths[@]}"; do
      [ -d "$pkg" ] || continue
      pkg="${pkg%/}/"           # ensure trailing slash for rel-path stripping
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
    if [ "${#conflicts[@]}" -gt 0 ]; then
      echo "check-conflicts: pre-existing paths would collide with stow:" >&2
      printf '  %s\n' "${conflicts[@]}" >&2
      cat >&2 <<'EOF'

    To resolve: back up each conflicting file and rerun. For example:
      mv ~/.zshrc ~/.zshrc.pre-stow.bak
    Then: just setup profile=<your-profile>
    EOF
      exit 1
    fi

# Setup on a fresh machine (install deps + link everything) for the resolved
# profile. Echoes a loud banner so the resolved profile and its source are
# visible at the start of every run.
setup profile="":
    #!/usr/bin/env bash
    set -euo pipefail
    ctx="$(just _profile-context "{{profile}}")"
    eval "$ctx"
    echo "Setup: profile=$profile (resolved from $source)"
    echo "Setting up for $(uname -s)..."
    just "$deps_recipe"
    just all profile="$profile"
    case "$profile" in
        linux-workstation) just setup-sway-session ;;
    esac

# Resolve+validate+derive profile dispatch context (WRK-002). Single source of
# truth used by every profile-aware recipe (setup, all, check-conflicts,
# unstow-all, restow, plan). Output contract: stdout is a series of `var=value`
# assignments, safe to `eval` into the caller's shell. Emitted values are
# alphanumeric+hyphen by construction (profile names, bucket names like
# `linux`/`macos`, recipe names like `install-deps-*`, lowercase package-name
# tokens), so `eval` is safe. Standalone-debuggable: `just _profile-context
# linux-remote` echoes the assignments without side effects.
#
# Resolution precedence: profile= arg > $DOTFILES_PROFILE > fail-loud. No OS
# default — if both are empty, exits 1 with the valid-profiles list for the
# current OS. OS:profile mismatch (e.g., mac-workstation on Linux) also exits 1.
#
# Caller pattern: capture-then-eval, NOT inline `eval "$(just _profile-context …)"`.
# Bash does not propagate failure from `$()` through `eval` even with
# inherit_errexit, so the inline form silently swallows the helper's exit-1.
# Recipes should do:
#     ctx="$(just _profile-context "{{profile}}")"
#     eval "$ctx"
# With `set -euo pipefail`, the assignment fails when the helper exits non-zero
# and the caller aborts before reaching eval. Helper's stderr (the error
# message) is already emitted at that point.
[private]
_profile-context profile="":
    #!/usr/bin/env bash
    set -euo pipefail

    os="$(uname -s)"
    case "$os" in
      Linux)  valid="linux-workstation linux-remote" ;;
      Darwin) valid="mac-workstation" ;;
      *)      echo "Unsupported OS: $os" >&2; exit 2 ;;
    esac

    # Resolve precedence: arg > env > fail-loud.
    # Normalize a leading "profile=" prefix so `just <recipe> profile=<name>`
    # (which just 1.x passes as the literal positional `profile=<name>`, not as
    # parameter binding) works the same as `just <recipe> <name>`.
    profile="{{profile}}"
    profile="${profile#profile=}"
    source=""
    if [ -n "$profile" ]; then
      source="arg"
    elif [ -n "${DOTFILES_PROFILE:-}" ]; then
      profile="$DOTFILES_PROFILE"
      source='$DOTFILES_PROFILE'
    else
      first="$(echo "$valid" | awk '{print $1}')"
      cat >&2 <<EOF
    No profile specified. Pass profile=<name> as an argument or export DOTFILES_PROFILE.

      just setup profile=$first
      DOTFILES_PROFILE=$first just setup

    Valid profiles for $os: $valid
    EOF
      exit 1
    fi

    # Validate against OS allowlist.
    case " $valid " in
      *" $profile "*) ;;
      *) echo "Profile '$profile' is not valid for OS $os. Valid profiles for $os: $valid" >&2; exit 1 ;;
    esac

    # Derive dispatch context.
    case "$profile" in
      linux-workstation) common_pkgs="{{packages_common_cli}} {{packages_common_workstation}}"
                         os_bucket="linux"
                         os_pkgs="{{packages_linux_workstation}}"
                         deps_recipe="install-deps-linux-workstation" ;;
      linux-remote)      common_pkgs="{{packages_common_cli}}"
                         os_bucket="linux"
                         os_pkgs="{{packages_linux_remote}}"
                         deps_recipe="install-deps-linux-remote" ;;
      mac-workstation)   common_pkgs="{{packages_common_cli}} {{packages_common_workstation}}"
                         os_bucket="macos"
                         os_pkgs="{{packages_macos_workstation}}"
                         deps_recipe="install-deps-mac-workstation" ;;
    esac

    # Emit sourceable assignment block.
    cat <<EOF
    profile="$profile"
    source="$source"
    common_pkgs="$common_pkgs"
    os_bucket="$os_bucket"
    os_pkgs="$os_pkgs"
    deps_recipe="$deps_recipe"
    EOF

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

# Install dependencies for the linux-workstation profile (Fedora dnf + GUI deps).
# Profile-blind: assumes it is being invoked on a Fedora host. Body lifted from
# the Linux branch of the legacy `install-deps` recipe (WRK-002 P3).
[private]
install-deps-linux-workstation:
    #!/usr/bin/env bash
    set -euo pipefail
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

# Install dependencies for the linux-remote profile (apt or dnf, CLI-only set,
# no GRUB/NVIDIA/flatpak/sway). Detects the package manager at runtime; fails
# loud on anything other than apt-get or dnf. install-zellij and install-yazi
# are already idempotent via `command -v` guards (WRK-002 P3).
[private]
install-deps-linux-remote:
    #!/usr/bin/env bash
    set -euo pipefail
    if command -v apt-get >/dev/null; then
        pm=apt
    elif command -v dnf >/dev/null; then
        pm=dnf
    else
        echo "Unsupported package manager. linux-remote v1 supports apt and dnf only. PRs welcome." >&2
        exit 1
    fi
    cli_deps="stow zsh tmux zoxide fzf neovim fd-find git curl unzip zsh-autosuggestions zsh-syntax-highlighting"
    case "$pm" in
        apt) sudo apt-get update && sudo apt-get install -y $cli_deps ;;
        dnf) sudo dnf install -y $cli_deps ;;
    esac
    just install-zellij
    just install-yazi

# Install dependencies for the mac-workstation profile (Homebrew). Profile-blind:
# assumes it is being invoked on a Darwin host. Body lifted from the Darwin
# branch of the legacy `install-deps` recipe (WRK-002 P3).
[private]
install-deps-mac-workstation:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v brew >/dev/null; then
        echo "Homebrew not found. Install from https://brew.sh" >&2
        exit 1
    fi
    # SketchyBar lives in a third-party tap, not core. Tap first so the
    # `brew install sketchybar` line below resolves.
    brew tap FelixKratz/formulae
    brew install stow zsh zoxide fzf zellij tmux neovim fd lazygit yazi sketchybar \
        zsh-autosuggestions zsh-syntax-highlighting
    # Cask installs are guarded for idempotency: brew --cask install errors
    # on already-installed in some versions. AeroSpace is in a third-party
    # tap (nikitabobko/tap), so install with the fully-qualified name; the
    # short name still works for the `brew list` idempotency probe.
    brew list --cask ghostty &>/dev/null || brew install --cask ghostty
    brew list --cask aerospace &>/dev/null || brew install --cask nikitabobko/tap/aerospace
    # Autostart sketchybar at login. Idempotent — `brew services start` is a
    # no-op if it's already running.
    brew services start sketchybar

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
