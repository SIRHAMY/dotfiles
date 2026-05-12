#!/usr/bin/env bash
set -euo pipefail

if [ "${DOTFILES_SKIP_EFS_STATE:-0}" = "1" ]; then
  echo "setup-efs-state: skipped because DOTFILES_SKIP_EFS_STATE=1"
  exit 0
fi

if [ -z "${EFS_MOUNT_POINT:-}" ]; then
  echo "setup-efs-state: EFS_MOUNT_POINT is unset; using local runtime state."
  exit 0
fi

mount_point="${EFS_MOUNT_POINT%/}"
state_root="${DOTFILES_EFS_STATE_ROOT:-$mount_point/state}"
prebuilt_home="${DOTFILES_PREBUILT_HOME:-/prebuilt-home}"

if [ ! -d "$mount_point" ]; then
  echo "setup-efs-state: $mount_point does not exist; using local runtime state." >&2
  exit 0
fi

if command -v mountpoint >/dev/null 2>&1 \
  && [ "${DOTFILES_EFS_ALLOW_UNMOUNTED:-0}" != "1" ] \
  && ! mountpoint -q "$mount_point"; then
  echo "setup-efs-state: $mount_point is not a mount point; using local runtime state." >&2
  echo "setup-efs-state: set DOTFILES_EFS_ALLOW_UNMOUNTED=1 to test against a normal directory." >&2
  exit 0
fi

timestamp="$(date +%Y%m%d-%H%M%S)"

is_empty_dir() {
  [ -d "$1" ] && [ -z "$(find "$1" -mindepth 1 -maxdepth 1 -print -quit)" ]
}

backup_path() {
  local path="$1"
  local backup="${path}.pre-efs.${timestamp}.bak"
  echo "setup-efs-state: backing up $path -> $backup"
  mv "$path" "$backup"
}

link_file_state() {
  local local_path="$1"
  local efs_path="$2"
  local init_mode="${3:-none}"

  mkdir -p "$(dirname "$local_path")" "$(dirname "$efs_path")"

  if [ -L "$local_path" ]; then
    local target
    target="$(readlink "$local_path")"
    if [ "$target" = "$efs_path" ]; then
      echo "setup-efs-state: $local_path already links to EFS"
    else
      echo "setup-efs-state: $local_path is a symlink to $target; leaving it unchanged." >&2
    fi
    return
  fi

  if [ -e "$local_path" ] && [ ! -e "$efs_path" ]; then
    echo "setup-efs-state: moving $local_path -> $efs_path"
    mv "$local_path" "$efs_path"
  elif [ -e "$local_path" ] && [ -e "$efs_path" ]; then
    if cmp -s "$local_path" "$efs_path"; then
      rm "$local_path"
    else
      backup_path "$local_path"
    fi
  elif [ ! -e "$efs_path" ]; then
    case "$init_mode" in
      empty) : > "$efs_path" ;;
      json) printf '{}\n' > "$efs_path" ;;
      none) ;;
      *) echo "setup-efs-state: unknown init mode '$init_mode'" >&2; exit 1 ;;
    esac
  fi

  if [ ! -e "$local_path" ]; then
    ln -s "$efs_path" "$local_path"
    echo "setup-efs-state: linked $local_path -> $efs_path"
  fi
}

link_dir_state() {
  local local_path="$1"
  local efs_path="$2"

  mkdir -p "$(dirname "$local_path")" "$(dirname "$efs_path")"

  if [ -L "$local_path" ]; then
    local target
    target="$(readlink "$local_path")"
    if [ "$target" = "$efs_path" ]; then
      echo "setup-efs-state: $local_path already links to EFS"
    else
      echo "setup-efs-state: $local_path is a symlink to $target; leaving it unchanged." >&2
    fi
    return
  fi

  if [ -e "$local_path" ] && [ ! -d "$local_path" ]; then
    backup_path "$local_path"
  fi

  if [ -d "$local_path" ] && [ ! -e "$efs_path" ]; then
    echo "setup-efs-state: moving $local_path -> $efs_path"
    mv "$local_path" "$efs_path"
  elif [ -d "$local_path" ] && [ -d "$efs_path" ]; then
    if is_empty_dir "$local_path"; then
      rmdir "$local_path"
    elif is_empty_dir "$efs_path"; then
      rmdir "$efs_path"
      echo "setup-efs-state: moving $local_path -> $efs_path"
      mv "$local_path" "$efs_path"
    else
      backup_path "$local_path"
    fi
  elif [ ! -e "$efs_path" ]; then
    mkdir -p "$efs_path"
  fi

  if [ ! -e "$local_path" ]; then
    ln -s "$efs_path" "$local_path"
    echo "setup-efs-state: linked $local_path -> $efs_path"
  fi
}

exclude_from_efs() {
  local rel="$1"
  rel="${rel#/}"
  local home_path="$HOME/$rel"
  local prebuilt_path="$prebuilt_home/$rel"

  if [ -L "$home_path" ]; then
    local target
    target="$(readlink "$home_path")"
    if [ "$target" = "$prebuilt_path" ]; then
      echo "setup-efs-state: $home_path already excluded -> $prebuilt_path"
      return
    fi
    echo "setup-efs-state: $home_path is a symlink to $target; leaving it unchanged." >&2
    return
  fi

  if ! mkdir -p "$prebuilt_path" 2>/dev/null; then
    echo "setup-efs-state: cannot create $prebuilt_path; skipping exclude for $home_path" >&2
    return
  fi

  if [ -e "$home_path" ]; then
    if [ -d "$home_path" ] && is_empty_dir "$home_path"; then
      rmdir "$home_path"
    else
      backup_path "$home_path"
    fi
  fi

  mkdir -p "$(dirname "$home_path")"
  ln -s "$prebuilt_path" "$home_path"
  echo "setup-efs-state: excluded $home_path -> $prebuilt_path"
}

if [ "$mount_point" = "$HOME" ]; then
  if [ ! -d "$prebuilt_home" ]; then
    echo "setup-efs-state: EFS mounted at HOME but $prebuilt_home is missing; cannot set up exclusions." >&2
    echo "setup-efs-state: set DOTFILES_PREBUILT_HOME or remount EFS off of HOME." >&2
    exit 0
  fi

  # Curated default excludes — paths that should NOT live on EFS.
  # Grouped by reason so future edits stay legible.
  default_excludes=(
    # Build/dependency caches — large, rebuildable, sometimes per-arch.
    ".cache"
    ".npm"
    ".yarn"
    ".pnpm-store"
    ".cargo"
    ".rustup"
    "go"
    ".gradle"
    ".m2"
    ".local/share/uv"
    ".local/share/virtualenvs"

    # IDE / language-server state — machine-specific, large.
    ".vscode-server"
    ".vscode-server-insiders"
    ".cursor-server"

    # Local daemon state — tied to the local Docker/etc daemon.
    ".docker"

    # Long-lived static credentials — must stay machine-local per security
    # policy. See README "EFS guardrails" for the rationale.
    ".aws"
    ".ssh"
    ".kube"
    ".config/gcloud"
  )

  if [ -n "${DOTFILES_EFS_EXCLUDES:-}" ]; then
    IFS=',' read -r -a excludes <<< "$DOTFILES_EFS_EXCLUDES"
  else
    excludes=("${default_excludes[@]}")
  fi

  if [ -n "${DOTFILES_EFS_EXTRA_EXCLUDES:-}" ]; then
    IFS=',' read -r -a extras <<< "$DOTFILES_EFS_EXTRA_EXCLUDES"
    excludes+=("${extras[@]}")
  fi

  # Dotfiles checkouts get excluded so the prebuilt clone wins over whatever
  # snapshot happens to be on EFS. Auto-detect any checkout under $HOME.
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  dotfiles_dir="$(cd "$script_dir/.." && pwd)"
  if [[ "$dotfiles_dir" == "$HOME/"* ]]; then
    excludes+=("${dotfiles_dir#$HOME/}")
  fi
  ai_dotfiles_dir="${AI_DOTFILES_DIR:-$HOME/Code/ai-dotfiles}"
  if [[ "$ai_dotfiles_dir" == "$HOME/"* ]]; then
    excludes+=("${ai_dotfiles_dir#$HOME/}")
  fi

  for rel in "${excludes[@]}"; do
    [ -z "$rel" ] && continue
    exclude_from_efs "$rel"
  done

  exit 0
fi

mkdir -p "$state_root/claude" "$state_root/codex" "$state_root/shell" "$HOME/.claude"

link_file_state "$HOME/.claude.json" "$state_root/claude/.claude.json" json
link_dir_state "$HOME/.claude/projects" "$state_root/claude/projects"
link_dir_state "$HOME/.claude/todos" "$state_root/claude/todos"

link_file_state "$HOME/.codex/config.toml" "$state_root/codex/config.toml" empty
link_file_state "$HOME/.codex/history.jsonl" "$state_root/codex/history.jsonl" empty
link_dir_state "$HOME/.codex/memories" "$state_root/codex/memories"
link_dir_state "$HOME/.codex/rules" "$state_root/codex/rules"
link_dir_state "$HOME/.codex/sessions" "$state_root/codex/sessions"

link_file_state "$HOME/.zsh_history" "$state_root/shell/zsh_history" empty

# Revocable per-user OAuth tokens — avoid re-login churn. Long-lived static creds stay local; see README.
link_file_state "$HOME/.claude/.credentials.json" "$state_root/claude/.credentials.json" empty
link_file_state "$HOME/.codex/auth.json" "$state_root/codex/auth.json" empty
link_dir_state "$HOME/.config/gh" "$state_root/gh"
link_dir_state "$HOME/.config/acli" "$state_root/acli"
