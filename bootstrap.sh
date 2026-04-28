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
exec just setup
