#!/usr/bin/env bash
set -euo pipefail

config_dir="$HOME/.config/opencode"
server_env="$config_dir/server.env"
default_config="$config_dir/config.json"
override_config="$config_dir/opencode.json"

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

mkdir -p "$config_dir"
migrate_default_config
report_higher_precedence_config

if [ -e "$server_env" ] || [ -L "$server_env" ]; then
  validate_server_env
  echo "setup-opencode-web: using private server environment file at $server_env."
else
  create_server_env
fi
