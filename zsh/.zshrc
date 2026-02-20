# --- History ---
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt SHARE_HISTORY          # share across sessions
setopt HIST_IGNORE_ALL_DUPS   # no duplicate entries
setopt HIST_REDUCE_BLANKS     # clean up whitespace

# --- Completion ---
autoload -Uz compinit && compinit
zstyle ':completion:*' menu select                    # arrow-key menu
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'  # case-insensitive

# --- Right-side prompt with timestamp ---
RPROMPT='%F{gray}%*%f'   # %* = HH:MM:SS, gray colored

# --- Left prompt (clean and useful) ---
PROMPT='%F{green}%~%f %# '   # working directory in green

# --- Key behaviors ---
bindkey '^[[A' history-beginning-search-backward   # up-arrow = history search
bindkey '^[[B' history-beginning-search-forward    # down-arrow = history search

# --- Useful defaults ---
setopt AUTO_CD          # type a directory name to cd into it
setopt CORRECT          # suggest corrections for typos
setopt GLOB_DOTS        # include dotfiles in glob patternssource /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

eval "$(zoxide init zsh)"
export PATH="/usr/local/bin:$PATH"
export PATH="/usr/local/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"
. "$HOME/.cargo/env"

# --- Aliases ---
alias clauded='claude --dangerously-skip-permissions'
alias vim='vimx'
# opencode
export PATH=/home/sirhamy/.opencode/bin:$PATH
