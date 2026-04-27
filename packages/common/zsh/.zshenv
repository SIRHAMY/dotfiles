: "${ZDOTDIR:=$HOME/.config/zsh}"
export ZDOTDIR

# zsh sources .zshenv once at startup using ZDOTDIR=$HOME (the default).
# Chain-source $ZDOTDIR/.zshenv so OS-specific buckets (e.g. zsh-macos's
# Homebrew shellenv bootstrap) actually run. Silent no-op when absent.
[ -r "$ZDOTDIR/.zshenv" ] && . "$ZDOTDIR/.zshenv"
