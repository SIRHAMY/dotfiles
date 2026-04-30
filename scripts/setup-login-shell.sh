#!/usr/bin/env bash
set -euo pipefail

if [ "${DOTFILES_SKIP_LOGIN_SHELL:-0}" = "1" ]; then
  echo "setup-login-shell: skipped because DOTFILES_SKIP_LOGIN_SHELL=1"
  exit 0
fi

if ! command -v zsh >/dev/null 2>&1; then
  echo "setup-login-shell: zsh not found; leaving login shell unchanged." >&2
  exit 0
fi

zsh_path="$(command -v zsh)"
user_name="${USER:-$(id -un)}"
current_shell="$(getent passwd "$user_name" 2>/dev/null | awk -F: '{print $7}')"

if [ "$current_shell" = "$zsh_path" ]; then
  echo "setup-login-shell: login shell already set to $zsh_path"
  exit 0
fi

if command -v sudo >/dev/null 2>&1 &&
  sudo -n true >/dev/null 2>&1 &&
  command -v usermod >/dev/null 2>&1; then
  sudo usermod --shell "$zsh_path" "$user_name"
  echo "setup-login-shell: changed $user_name login shell to $zsh_path"
  exit 0
fi

cat >&2 <<EOF
setup-login-shell: could not change login shell automatically.
Current shell: ${current_shell:-unknown}
Wanted shell:  $zsh_path

The bash startup shim is still installed as a fallback. To change the login
shell manually on this host, run:
  sudo usermod --shell "$zsh_path" "$user_name"
EOF
