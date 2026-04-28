#!/usr/bin/env bash
set -euo pipefail

: "${DOTFILES_PROFILE:=linux-remote}"
export DOTFILES_PROFILE

if ! command -v just >/dev/null; then
  echo "bootstrap.sh: 'just' not found on PATH." >&2
  echo "Install with: curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh | bash -s -- --to /usr/local/bin" >&2
  exit 1
fi

cd "$(dirname "$0")"

# Auto-backup pre-existing files that would collide with stow. Required for
# unattended installs on remote dev envs (Ona, Codespaces) whose base images
# ship rcs like ~/.bashrc and ~/.zshenv as real files. Originals move to
# *.pre-stow.<timestamp>.bak; nothing is deleted.
conflicts="$(just check-conflicts 2>&1 || true)"
if printf '%s\n' "$conflicts" | grep -q '^check-conflicts: pre-existing paths'; then
  ts="$(date +%Y%m%d-%H%M%S)"
  echo "bootstrap.sh: backing up pre-stow conflicts to *.pre-stow.${ts}.bak"
  printf '%s\n' "$conflicts" | sed -n 's|^  \(/[^ ]*\) .*|\1|p' | while read -r path; do
    [ -z "$path" ] && continue
    backup="${path}.pre-stow.${ts}.bak"
    echo "  $path -> $backup"
    mv "$path" "$backup"
  done
fi

exec just setup
