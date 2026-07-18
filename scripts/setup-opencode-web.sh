#!/usr/bin/env bash
set -euo pipefail

profile="${1:-}"
phase="${2:-}"
config_dir="$HOME/.config/opencode"
server_env="$config_dir/server.env"
default_config="$config_dir/config.json"
override_config="$config_dir/opencode.json"
opencode_bin="$HOME/.opencode/bin/opencode"

fail() {
  echo "setup-opencode-web: $*" >&2
  exit 1
}

require_command() {
  local command_name="$1"

  command -v "$command_name" >/dev/null 2>&1 || fail "missing required command '$command_name'."
}

verify_opencode() {
  if [ ! -f "$opencode_bin" ] || [ ! -x "$opencode_bin" ]; then
    fail "expected executable OpenCode binary at $opencode_bin."
  fi
}

verify_user_systemd() {
  require_command loginctl
  require_command systemctl
  systemctl --user show-environment >/dev/null 2>&1 || fail "cannot access the user systemd manager; start a user session with a working systemd user bus."
}

verify_tailscale() {
  local tailscale_status

  require_command tailscale
  if ! tailscale_status="$(tailscale status --json 2>/dev/null)"; then
    fail "Tailscale is unavailable; connect it and rerun."
  fi

  if [[ ! "$tailscale_status" =~ \"BackendState\"[[:space:]]*:[[:space:]]*\"Running\" ]]; then
    fail "Tailscale is disconnected; connect it and rerun."
  fi
}

verify_profile() {
  case "$profile" in
    linux-workstation|linux-remote) ;;
    *) fail "expected Linux profile, got '${profile:-empty}'." ;;
  esac
}

verify_phase() {
  case "$phase" in
    migrate|provision) ;;
    *) fail "expected setup phase 'migrate' or 'provision', got '${phase:-empty}'." ;;
  esac
}

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "setup-opencode-web: jq is required to migrate $default_config safely; install jq and rerun." >&2
    exit 1
  fi
}

validate_json_object() {
  local config_path="$1"

  if ! jq -e 'type == "object"' "$config_path" >/dev/null; then
    echo "setup-opencode-web: $config_path must contain a valid JSON object; fix it or move it aside, then rerun." >&2
    exit 1
  fi
}

backup_config() {
  local config_path="$1"
  local backup_path="${config_path}.pre-opencode-web.${backup_suffix}.bak"

  if [ -e "$backup_path" ] || [ -L "$backup_path" ]; then
    echo "setup-opencode-web: backup path $backup_path already exists; move it aside and rerun." >&2
    exit 1
  fi

  cp -p "$config_path" "$backup_path"
}

migrate_default_config() {
  local merged_config

  [ -L "$default_config" ] && return
  [ ! -e "$default_config" ] && return
  if [ ! -f "$default_config" ]; then
    echo "setup-opencode-web: $default_config must be a regular file; move it aside and rerun." >&2
    exit 1
  fi

  require_jq
  validate_json_object "$default_config"

  if [ ! -e "$override_config" ] && [ ! -L "$override_config" ]; then
    backup_suffix="$(date +%Y%m%d-%H%M%S)"
    backup_config "$default_config"
    mv "$default_config" "$override_config"
    echo "setup-opencode-web: migrated $default_config to higher-precedence $override_config."
    return
  fi

  if [ -L "$override_config" ] || [ ! -f "$override_config" ]; then
    echo "setup-opencode-web: $override_config must be a regular file; move it aside and rerun." >&2
    exit 1
  fi

  validate_json_object "$override_config"
  merged_config="$(mktemp "$config_dir/.opencode.json.XXXXXX")"
  if ! jq -s '.[0] * .[1]' "$default_config" "$override_config" > "$merged_config"; then
    rm -f "$merged_config"
    echo "setup-opencode-web: could not merge $default_config into $override_config; fix the JSON and rerun." >&2
    exit 1
  fi

  backup_suffix="$(date +%Y%m%d-%H%M%S)"
  backup_config "$default_config"
  backup_config "$override_config"
  if ! mv "$merged_config" "$override_config"; then
    rm -f "$merged_config"
    exit 1
  fi
  rm "$default_config"
  echo "setup-opencode-web: merged $default_config below $override_config."
}

report_overriding_policy() {
  local config_path="$1"
  local policy_name="$2"

  if grep -Eq "\"${policy_name}\"[[:space:]]*:" "$config_path"; then
    echo "setup-opencode-web: $config_path defines '$policy_name' and overrides the stowed default." >&2
  fi
}

report_higher_precedence_config() {
  local config_path

  for config_path in "$config_dir/opencode.json" "$config_dir/opencode.jsonc"; do
    [ -f "$config_path" ] || continue
    echo "setup-opencode-web: preserving higher-precedence config $config_path." >&2
    report_overriding_policy "$config_path" permission
    report_overriding_policy "$config_path" share
  done
}

create_server_env() {
  local temporary_env
  local password

  mkdir -p "$config_dir"
  temporary_env="$(mktemp "$config_dir/.server.env.XXXXXX")"
  trap 'rm -f "$temporary_env"' EXIT
  password="$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')"
  printf 'OPENCODE_SERVER_PASSWORD=%s\n' "$password" > "$temporary_env"
  mv "$temporary_env" "$server_env"
  trap - EXIT
  echo "setup-opencode-web: created private server environment file at $server_env."
}

validate_server_env() {
  if [ -L "$server_env" ] || [ ! -f "$server_env" ]; then
    echo "setup-opencode-web: $server_env must be a regular private file, not a symlink." >&2
    exit 1
  fi

  chmod 600 "$server_env"
  if ! grep -Eq '^OPENCODE_SERVER_PASSWORD=.+$' "$server_env"; then
    echo "setup-opencode-web: $server_env must define OPENCODE_SERVER_PASSWORD." >&2
    exit 1
  fi
}

verify_profile
verify_phase
verify_opencode
verify_user_systemd
if [ "$profile" = "linux-workstation" ]; then
  verify_tailscale
fi
mkdir -p "$config_dir"
migrate_default_config
report_higher_precedence_config

if [ -e "$server_env" ] || [ -L "$server_env" ]; then
  validate_server_env
  echo "setup-opencode-web: using private server environment file at $server_env."
else
  create_server_env
fi

if [ "$phase" = "migrate" ]; then
  exit 0
fi

systemctl --user daemon-reload
loginctl enable-linger "$USER"
systemctl --user enable --now opencode-web.service

if [ "$profile" = "linux-workstation" ]; then
  tailscale serve --bg http://127.0.0.1:4096
fi
