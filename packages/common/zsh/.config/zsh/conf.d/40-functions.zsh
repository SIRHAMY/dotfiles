# --- Functions ---
zp() {
  local active_sessions=$(zellij list-sessions --short 2>/dev/null)
  local project_list=""
  typeset -A project_paths
  local roots=("$HOME/Code" "/workspaces")
  for root in "${roots[@]}"; do
    [[ -d "$root" ]] || continue
    for dir in "$root"/*/; do
      [[ -d "$dir" ]] || continue
      local name=$(basename "$dir")
      # First root wins on name collisions; preserves $HOME/Code precedence.
      [[ -n "${project_paths[$name]:-}" ]] && continue
      project_paths[$name]="${dir%/}"
      if echo "$active_sessions" | grep -qx "$name"; then
        project_list+="* $name"$'\n'
      else
        project_list+="  $name"$'\n'
      fi
    done
  done

  local selected=$(echo -n "$project_list" | fzf --reverse --prompt="project > ")
  [[ -z "$selected" ]] && return
  local name=$(echo "$selected" | sed 's/^[* ] *//')

  cd "${project_paths[$name]}" && zellij -l dev attach "$name" -c
}

_ona_require_commands() {
  local missing=()
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done
  if (( ${#missing[@]} )); then
    print -u2 "ona-ssh: missing command(s): ${missing[*]}"
    return 127
  fi
}

_ona_has_name_flag() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      --name|--name=*)
        return 0
        ;;
    esac
  done
  return 1
}

_ona_create_target() {
  local arg
  local expects_value=0

  for arg in "$@"; do
    if (( expects_value )); then
      expects_value=0
      continue
    fi

    case "$arg" in
      --class-id|--config|--context|--editor|--log-format|--name|--timeout)
        expects_value=1
        ;;
      --*=*|--dont-wait|--interactive|--logs|-i|-v)
        ;;
      -*)
        ;;
      *)
        printf '%s\n' "$arg"
        return
        ;;
    esac
  done

  printf 'ona\n'
}

_ona_environment_name_subject() {
  local target="${1:-ona}"
  local subject

  target="${target%%\#*}"
  target="${target%%\?*}"
  target="${target%/}"
  target="${target%.git}"
  subject="${target##*/}"
  subject="${subject##*:}"
  subject=$(printf '%s' "$subject" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')
  [[ -n "$subject" ]] || subject="ona"
  printf '%s\n' "$subject"
}

_ona_generated_environment_name() {
  local target="${1:-ona}"
  local subject timestamp suffix max_subject_length

  subject=$(_ona_environment_name_subject "$target") || return
  timestamp=$(date '+%Y%m%dT%H%M%S') || return
  suffix="-$timestamp"
  max_subject_length=$(( 80 - ${#suffix} ))

  if (( ${#subject} > max_subject_length )); then
    subject="${subject[1,$max_subject_length]}"
    subject="${subject%-}"
  fi
  [[ -n "$subject" ]] || subject="ona"

  printf '%s%s\n' "$subject" "$suffix"
}

_ona_pick_running_env() {
  local json rows env_id

  json=$(ona environment list --running-only --format json) || return
  rows=$(
    printf '%s\n' "$json" | jq -r '
      def parse_time:
        if . == null or . == "" then null
        else sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601
        end;
      def age:
        parse_time as $t |
        if $t == null then "-"
        else ((now - $t) / 3600 | floor) as $h |
          if $h < 24 then "\($h)h" else "\(($h / 24) | floor)d" end
        end;
      def active:
        parse_time as $t |
        if $t == null then "-"
        else ((now - $t) / 60 | floor) as $m |
          if $m < 60 then "\($m)m ago"
          elif $m < 1440 then "\(($m / 60) | floor)h ago"
          else "\(($m / 1440) | floor)d ago" end
        end;
      .[] |
      .metadata as $m | .status as $s |
      [
        ($m.name // "-"),
        ($s.content.git.branch // "-"),
        ($m.createdAt | age),
        ($s.activitySignal.timestamp | active),
        .id
      ] | @tsv'
  ) || return

  if [[ -z "$rows" ]]; then
    print -u2 "ona-ssh: no running environments found."
    return 1
  fi

  env_id=$(
    {
      printf 'NAME\tBRANCH\tAGE\tACTIVE\tID\n'
      printf '%s\n' "$rows"
    } | column -t -s $'\t' | fzf --header-lines=1 --prompt="ona env > " | awk '{print $NF}'
  ) || return

  [[ -n "$env_id" ]] && printf '%s\n' "$env_id"
}

ona-ssh() {
  local mode="${ONA_SSH_MODE:-zellij}"
  local session="${ONA_SSH_SESSION:-main}"
  local layout="${ONA_SSH_LAYOUT:-dev}"
  local env_id remote_cmd remote_term remote_colorterm
  local remote_shell_setup='if command -v zsh >/dev/null 2>&1; then export SHELL="$(command -v zsh)"; fi'
  local remote_shell_fallback='if [ -n "${SHELL:-}" ] && [ -x "$SHELL" ]; then exec "$SHELL" -l; else exec /bin/sh -l; fi'

  remote_term="${ONA_SSH_TERM:-xterm-256color}"
  remote_colorterm="${ONA_SSH_COLORTERM:-truecolor}"
  local remote_term_setup="export TERM=${remote_term:q}; export COLORTERM=${remote_colorterm:q}"

  case "${1:-}" in
    --plain)
      mode=plain
      shift
      ;;
    --tmux)
      mode=tmux
      shift
      ;;
    --zellij)
      mode=zellij
      shift
      ;;
    -h|--help)
      cat <<'EOF'
Usage: ona-ssh [--tmux|--zellij|--plain] [environment-id]

Pick a running Ona environment with fzf, then SSH into it.
With an environment ID or unique partial ID, skips the picker.

Modes:
  --zellij  Attach/create remote zellij session named $ONA_SSH_SESSION, default main.
            New zellij sessions use layout $ONA_SSH_LAYOUT, default dev.
  --tmux    Attach/create remote tmux session named $ONA_SSH_SESSION, default main.
  --plain   Open a fixed-term remote shell without zellij/tmux.

Default mode: $ONA_SSH_MODE, or zellij when unset.
EOF
      return
      ;;
  esac

  command -v ona >/dev/null 2>&1 || {
    print -u2 "ona-ssh: missing command: ona"
    return 127
  }

  env_id="${1:-}"
  if [[ -z "$env_id" ]]; then
    _ona_require_commands jq fzf column awk || return
    env_id=$(_ona_pick_running_env) || return
  fi

  case "$mode" in
    plain)
      remote_cmd="${remote_shell_setup}; ${remote_term_setup}; ${remote_shell_fallback}"
      ona environment ssh "$env_id" -- -t "$remote_cmd"
      ;;
    tmux)
      remote_cmd="${remote_shell_setup}; ${remote_term_setup}; if command -v tmux >/dev/null 2>&1; then [ -n \"\${SHELL:-}\" ] && tmux set-option -g default-shell \"\$SHELL\" >/dev/null 2>&1 || true; exec tmux new-session -A -s ${session:q}; else ${remote_shell_fallback}; fi"
      ona environment ssh "$env_id" -- -t "$remote_cmd"
      ;;
    zellij)
      remote_cmd="${remote_shell_setup}; ${remote_term_setup}; if command -v zellij >/dev/null 2>&1; then exec zellij -l ${layout:q} attach ${session:q} -c; else ${remote_shell_fallback}; fi"
      ona environment ssh "$env_id" -- -t "$remote_cmd"
      ;;
    *)
      print -u2 "ona-ssh: unknown mode '$mode' (expected tmux, zellij, or plain)"
      return 2
      ;;
  esac
}

ona-up() {
  if [[ $# -eq 0 || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'EOF'
Usage: ona-up <repo-url|project-id> [ona environment create flags...]

Create a uniquely named Ona environment, wait for it to start, then run ona-ssh.
Pass --name to override the generated <project>-<timestamp> name.
EOF
    return $(( $# == 0 ? 2 : 0 ))
  fi

  if _ona_has_name_flag "$@"; then
    ona environment create "$@" && ona-ssh
    return
  fi

  local target env_name
  target=$(_ona_create_target "$@") || return
  env_name=$(_ona_generated_environment_name "$target") || return

  ona environment create "$@" --name "$env_name" && ona-ssh
}

# Default port set forwarded by ona-dev-forward. Each entry is "PORT" (forwards
# localhost:PORT -> remote localhost:PORT) or "LOCAL:REMOTE". Tuned for a
# typical compose-based dev stack: web frontends, log viewer, node debugger,
# GraphQL playground, and the usual datastores so local IDE tools (DB clients,
# RedisInsight, S3 browsers) Just Work against the remote env.
typeset -ga _ONA_DEV_FORWARD_DEFAULT_PORTS
_ONA_DEV_FORWARD_DEFAULT_PORTS=(
  # web / frontend
  8000   # backend dev server
  8080   # web nginx (integration variant) — also serves /_logs
  8081   # web nginx (default variant)
  9000   # frontend dev server (parcel)
  8181   # dozzle log viewer (direct)
  # debugger / tooling
  9229   # node inspector — attach VS Code or chrome://inspect
  3500   # graphiql
  # datastores
  27017  # mongo
  27018  # global mongo
  5432   # postgres
  6379   # redis
  6380   # bullmq redis
  3306   # mysql
  # AWS local emulation
  4566   # localstack edge
  9001   # minio admin console
)

ona-dev-forward() {
  local env_id

  case "${1:-}" in
    -h|--help)
      cat <<EOF
Usage: ona-dev-forward [environment-id] [extra-port ...]

Forward common dev ports from a running Ona environment to localhost.
With no environment-id, fzf-pick from running envs (same picker as ona-ssh).

Defaults: ${_ONA_DEV_FORWARD_DEFAULT_PORTS[*]}

Override entirely:
  ONA_DEV_FORWARD_PORTS=8080,9000,5432 ona-dev-forward
Each item is PORT or LOCAL:REMOTE.

Add extras alongside the defaults:
  ona-dev-forward <env-id> 9092 5555 8083

Common extras (uncomment the workflow you need):
  9092   kafka broker        8083   kafka connect       17265 schema-registry
  10289  oso authz           3020   oplog-monitor       5555  datadog-agent
  9002   minio S3 API        3000   turbo cache

Failures on individual -L bindings are non-fatal warnings — one taken local
port won't kill the whole tunnel.
EOF
      return 0
      ;;
  esac

  command -v ona >/dev/null 2>&1 || {
    print -u2 "ona-dev-forward: missing command: ona"
    return 127
  }

  # First positional is treated as an env-id only when it looks like a UUID;
  # everything else is treated as an extra port spec.
  if [[ -n "${1:-}" && "$1" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
    env_id="$1"
    shift
  fi

  local -a ports
  if [[ -n "${ONA_DEV_FORWARD_PORTS:-}" ]]; then
    ports=("${(@s:,:)ONA_DEV_FORWARD_PORTS}")
  else
    ports=("${_ONA_DEV_FORWARD_DEFAULT_PORTS[@]}")
  fi
  ports+=("$@")

  local -a forward_args
  local spec local_port remote_port
  for spec in "${ports[@]}"; do
    spec="${spec// /}"
    [[ -z "$spec" ]] && continue
    if [[ "$spec" == *:* ]]; then
      local_port="${spec%%:*}"
      remote_port="${spec##*:}"
    else
      local_port="$spec"
      remote_port="$spec"
    fi
    if ! [[ "$local_port" =~ ^[0-9]+$ && "$remote_port" =~ ^[0-9]+$ ]]; then
      print -u2 "ona-dev-forward: invalid port spec '$spec'"
      return 2
    fi
    forward_args+=(-L "${local_port}:localhost:${remote_port}")
  done

  if (( ${#forward_args[@]} == 0 )); then
    print -u2 "ona-dev-forward: no ports to forward"
    return 2
  fi

  if [[ -z "$env_id" ]]; then
    _ona_require_commands jq fzf column awk || return
    env_id=$(_ona_pick_running_env) || return
  fi

  print -u2 "ona-dev-forward: forwarding to ${env_id} (Ctrl-C to stop)"
  for spec in "${ports[@]}"; do
    [[ -z "$spec" ]] && continue
    print -u2 "  localhost:${spec%%:*}"
  done

  ona environment ssh "$env_id" -- -N "${forward_args[@]}"
}
