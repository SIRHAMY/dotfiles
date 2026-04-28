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
