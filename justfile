packages := "zsh tmux git bash ghostty sway waybar mako environment.d zellij"

# Link all packages
all:
    @for pkg in {{packages}}; do \
        echo "Stowing $pkg..."; \
        stow -t ~ $pkg; \
    done
    @echo "Done! All packages linked."

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
