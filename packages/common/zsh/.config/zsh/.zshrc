# ~/.config/zsh/.zshrc  (stowed from packages/common/zsh)
# Filesystem-based OS dispatch. No case $OSTYPE inside snippets.
# conf.d/ is kept un-folded by a .gitkeep in packages/common/zsh — do not delete.

# Fast OS-key dispatch (no fork in common cases). Fallback handles WSL and
# anything unusual.
case "$OSTYPE" in
  darwin*) os_key=darwin ;;
  linux*)  os_key=linux ;;
  *)       os_key="$(uname -s | tr '[:upper:]' '[:lower:]')" ;;
esac

ZDOTCONFD="${ZDOTDIR:-$HOME/.config/zsh}/conf.d"

# null_glob: a no-match glob expands to nothing (missing dir = tolerated).
# Errors from source (syntax errors, unreadable files) print to stderr and
# the for loop continues — we deliberately do NOT `|| print` here, because
# it would also fire on snippets whose last command legitimately returns
# non-zero (e.g. a guarded `[ -d X ] && ...`).
setopt null_glob
for f in "$ZDOTCONFD"/*.zsh "$ZDOTCONFD/os.$os_key"/*.zsh; do
  [ -r "$f" ] || continue
  source "$f"
done
unsetopt null_glob
unset ZDOTCONFD os_key
