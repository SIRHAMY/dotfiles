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

# --- Key behaviors ---
bindkey '^[[A' history-beginning-search-backward   # up-arrow = history search
bindkey '^[[B' history-beginning-search-forward    # down-arrow = history search

# --- Useful defaults ---
setopt AUTO_CD          # type a directory name to cd into it
setopt CORRECT          # suggest corrections for typos
setopt GLOB_DOTS        # include dotfiles in glob patterns
