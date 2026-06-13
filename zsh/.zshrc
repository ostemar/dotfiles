# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# ============================================================================
# SYSTEM COMPATIBILITY NOTES
# ============================================================================
# This .zshrc works across:
#   - Native Linux (Ubuntu 24.04 LTS tested)
#   - WSL (Windows Subsystem for Linux)
#
# Optional dependencies (gracefully skipped if not installed):
#   - Homebrew (/home/linuxbrew/.linuxbrew/bin/brew)
#   - NVM (Node Version Manager)
#   - Custom env file (~/.local/bin/env)
# ============================================================================

# Set the directory we want to store zinit and plugins
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"

# Download Zinit, if it's not there yet.
# Guard on zinit.zsh (not just the dir) so an interrupted clone self-heals:
# a half-finished clone leaves the directory behind but no zinit.zsh.
if [ ! -f "$ZINIT_HOME/zinit.zsh" ]; then
   rm -rf "$ZINIT_HOME"
   mkdir -p "$(dirname $ZINIT_HOME)"
   git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi

# Source/Load zinit
source "${ZINIT_HOME}/zinit.zsh"

# Add in Powerlevel10k
zinit ice depth=1; zinit light romkatv/powerlevel10k

# Add in zsh plugins
zinit light zsh-users/zsh-syntax-highlighting
zinit light zsh-users/zsh-completions
zinit light zsh-users/zsh-autosuggestions
zinit light Aloxaf/fzf-tab

# Add in snippets
zinit snippet OMZP::git
zinit snippet OMZP::command-not-found

# Always exclude docker completion
fpath=(${fpath:#/usr/share/zsh/vendor-completions})

# Conditionally load Docker completions if Docker is available
# if command -v docker &> /dev/null; then
#    # Load Docker completions
#    if [[ -d "/usr/share/zsh/vendor-completions" ]]; then
#        fpath=("/usr/share/zsh/vendor-completions" $fpath)
#    fi
# fi
#
# # Remove broken _docker completion if it's a broken symlink
# if [ -L /usr/share/zsh/vendor-completions/_docker ] && [ ! -e /usr/share/zsh/vendor-completions/_docker ]; then
#   fpath=(${fpath:#/usr/share/zsh/vendor-completions})
# fi

# Load completions
autoload -Uz compinit && compinit
zinit cdreplay -q

# Nice prompt
# eval "$(starship init zsh)"
# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# Homebrew (if installed)
# Note: Homebrew for Linux installs to /home/linuxbrew/.linuxbrew
if [[ -x "/home/linuxbrew/.linuxbrew/bin/brew" ]]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

# Key bindings
bindkey '^f' autosuggest-accept
bindkey '^p' history-search-backward
bindkey '^n' history-search-forward

# Aliases
# alias ls='ls --color'
alias v='nvim'
alias nv='nvim'
alias c='clear'
# alias ll="exa -l -g --icons --git"
# alias llt="exa -1 --icons --tree --git-ignore"
alias ls="exa --icons"
alias ll="exa --all -l -g --icons"
alias llt="exa -1 --icons --tree"
alias la='exa --all --icons'
# alias ll='ls -alF'
# alias la='ls -A'
alias l='ls -CF'
alias bat='batcat'
alias lg='lazygit'

# History
HISTSIZE=5000
HISTFILE=~/.zsh_history
SAVEHIST=$HISTSIZE
HISTDUP=erase
setopt appendhistory
setopt sharehistory
setopt hist_ignore_space
setopt hist_ignore_all_dups
setopt hist_save_no_dups
setopt hist_ignore_dups
setopt hist_find_no_dups

# Completions
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' menu no
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls --color $realpath'
# zstyle ':fzf-tab:complete:__zoxide_z:*' fzf-preview 'ls --color $realpath'

# Shell integrations
# fzf - Fuzzy finder integration
# Note: fzf 0.48+ supports --zsh flag. Ubuntu 24.04 LTS has 0.44.1, so we use the legacy method.
# When upgrading to Ubuntu 25.04+ or fzf 0.48+, replace these lines with: eval "$(fzf --zsh)"
if command -v fzf &> /dev/null; then
  if [[ -f /usr/share/doc/fzf/examples/key-bindings.zsh ]]; then
    source /usr/share/doc/fzf/examples/key-bindings.zsh
  fi
  if [[ -f /usr/share/doc/fzf/examples/completion.zsh ]]; then
    source /usr/share/doc/fzf/examples/completion.zsh
  fi
fi

# zoxide - Smarter cd command
eval "$(zoxide init --cmd cd zsh)"

# NVM (Node Version Manager) - if installed
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# Rust (rustup) - if installed. Puts ~/.cargo/bin on PATH.
[ -s "$HOME/.cargo/env" ] && \. "$HOME/.cargo/env"

# Go - if installed via official tarball (/usr/local/go). Also expose ~/go/bin
# for `go install`-ed binaries.
if [[ -d /usr/local/go/bin ]] && [[ ":$PATH:" != *":/usr/local/go/bin:"* ]]; then
  export PATH="$PATH:/usr/local/go/bin:$HOME/go/bin"
fi

# Add ~/.local/bin to PATH if not already there
# This is where user-installed tools (pip, uv, cargo, etc.) place binaries
if [[ -d "$HOME/.local/bin" ]] && [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
  export PATH="$HOME/.local/bin:$PATH"
fi

# Source additional environment config if it exists
if [[ -f "$HOME/.local/bin/env" ]]; then
  . "$HOME/.local/bin/env"
fi

# opencode
export PATH=/home/martin/.opencode/bin:$PATH
