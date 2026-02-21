packages := "zsh tmux git bash ghostty sway swaylock waybar mako environment.d zellij bin"

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
    @echo "Installing dependencies..."
    @command -v stow >/dev/null || (echo "Installing stow..." && sudo dnf install -y stow)
    @command -v zsh >/dev/null || (echo "Installing zsh..." && sudo dnf install -y zsh)
    @command -v zoxide >/dev/null || (echo "Installing zoxide..." && sudo dnf install -y zoxide)
    @just all
    @just reload

# Reload running apps to pick up config changes
reload:
    @echo "Reloading apps..."
    @pgrep waybar >/dev/null && killall -SIGUSR2 waybar && echo "Reloaded waybar" || true
    @pgrep mako >/dev/null && makoctl reload && echo "Reloaded mako" || true
    @pgrep sway >/dev/null && swaymsg reload >/dev/null && echo "Reloaded sway" || true
    @echo "Done!"
