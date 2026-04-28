# Portable PATH (deduped) + zoxide init.
export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"

command -v zoxide >/dev/null && eval "$(zoxide init zsh)"
