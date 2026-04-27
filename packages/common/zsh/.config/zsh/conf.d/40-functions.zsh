# --- Functions ---
zp() {
  local active_sessions=$(zellij list-sessions --short 2>/dev/null)
  local project_list=""
  for dir in "$HOME"/Code/*/; do
    [[ -d "$dir" ]] || continue
    local name=$(basename "$dir")
    if echo "$active_sessions" | grep -qx "$name"; then
      project_list+="* $name"$'\n'
    else
      project_list+="  $name"$'\n'
    fi
  done

  local selected=$(echo -n "$project_list" | fzf --reverse --prompt="project > ")
  [[ -z "$selected" ]] && return
  local name=$(echo "$selected" | sed 's/^[* ] *//')

  cd "$HOME/Code/$name" && zellij -l dev attach "$name" -c
}
