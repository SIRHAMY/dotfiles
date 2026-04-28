#!/usr/bin/env bash
set -euo pipefail

repo="${AI_DOTFILES_REPO:-git@github.com:SIRHAMY/ai-dotfiles.git}"
dir="${AI_DOTFILES_DIR:-$HOME/Code/ai-dotfiles}"

if [ "${DOTFILES_SKIP_AI_DOTFILES:-0}" = "1" ]; then
  echo "setup-ai-dotfiles: skipped because DOTFILES_SKIP_AI_DOTFILES=1"
  exit 0
fi

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "setup-ai-dotfiles: '$1' is required but was not found on PATH." >&2
    exit 1
  fi
}

require_cmd git
require_cmd just

mkdir -p "$(dirname "$dir")" "$HOME/.claude"

if [ -e "$dir" ] && [ ! -d "$dir/.git" ]; then
  cat >&2 <<EOF
setup-ai-dotfiles: $dir exists but is not a git checkout.
Move it aside or set AI_DOTFILES_DIR to a different path.
EOF
  exit 1
fi

if [ ! -d "$dir/.git" ]; then
  echo "setup-ai-dotfiles: cloning $repo -> $dir"
  git clone "$repo" "$dir"
elif [ "${AI_DOTFILES_SKIP_UPDATE:-0}" = "1" ]; then
  echo "setup-ai-dotfiles: update skipped because AI_DOTFILES_SKIP_UPDATE=1"
elif [ -n "$(git -C "$dir" status --porcelain)" ]; then
  echo "setup-ai-dotfiles: $dir has local changes; skipping pull and linking current checkout."
elif git -C "$dir" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
  echo "setup-ai-dotfiles: updating $dir"
  git -C "$dir" pull --ff-only
else
  echo "setup-ai-dotfiles: $dir has no upstream; skipping pull and linking current checkout."
fi

if [ ! -f "$dir/justfile" ]; then
  echo "setup-ai-dotfiles: $dir does not contain a justfile." >&2
  exit 1
fi

echo "setup-ai-dotfiles: linking Claude config"
(
  cd "$dir"
  just link
)
