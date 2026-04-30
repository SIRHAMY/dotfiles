[ -r "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
[ -d "$HOME/.opencode/bin" ] && PATH="$HOME/.opencode/bin:$PATH"

if [[ "${TERM:-}" == "xterm-ghostty" ]] && ! infocmp "$TERM" >/dev/null 2>&1; then
  export TERM=xterm-256color
fi
export COLORTERM="${COLORTERM:-truecolor}"
