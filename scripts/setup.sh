#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------
# Linux dotfiles setup
# - Links Neovim config and other ~/.config items
# - Links bat config to ~/.config/bat
# - Links ~/.zshrc from repo/zsh/.zshrc
# - Changes default shell to zsh (if zsh is installed)
# - Idempotent: backs up existing paths unless --force
# - Supports --dry-run and --repo
# ---------------------------------------------

# Defaults
DRY_RUN=0
FORCE=0
REPO_ROOT=""
XDG_CONFIG_HOME_DEFAULT="${XDG_CONFIG_HOME:-$HOME/.config}"

# ---------- Helpers ----------
log() { printf "%s\n" "$*"; }
info() { printf "🔗 %s\n" "$*"; }
ok() { printf "✅ %s\n" "$*"; }
warn() { printf "⚠️  %s\n" "$*" >&2; }
err() { printf "❌ %s\n" "$*" >&2; }

usage() {
    cat <<EOF
Usage: $0 [--repo PATH] [--dry-run] [--force]

Options:
  --repo PATH   Path to repo root (defaults to parent of this script)
  --dry-run     Show actions without changing anything
  --force       Overwrite existing files/dirs instead of backing them up
EOF
}

is_wsl() {
    grep -qi microsoft /proc/version 2>/dev/null
}

abs_path() {
    # Resolve absolute path without realpath dependency
    local p="$1"
    if [ -d "$p" ]; then (cd "$p" && pwd -P); else (cd "$(dirname "$p")" && printf "%s/%s\n" "$(pwd -P)" "$(basename "$p")"); fi
}

backup_or_remove() {
    # $1 = existing path
    local existing="$1"
    if [ $FORCE -eq 1 ]; then
        [ $DRY_RUN -eq 1 ] && {
            info "Would remove: $existing"
            return
        }
        rm -rf -- "$existing"
        return
    fi
    local ts
    ts="$(date +%Y%m%d-%H%M%S)"
    local backup="${existing}.bak.${ts}"
    [ $DRY_RUN -eq 1 ] && {
        info "Would backup: $existing -> $backup"
        return
    }
    mv -- "$existing" "$backup"
    warn "Backed up $existing -> $backup"
}

ensure_parent_dir() {
    local path="$1"
    local dir
    dir="$(dirname "$path")"
    if [ ! -d "$dir" ]; then
        [ $DRY_RUN -eq 1 ] && {
            info "Would mkdir -p $dir"
            return
        }
        mkdir -p -- "$dir"
    fi
}

link_path() {
    # $1 = target (source in repo), $2 = link path (dest in $HOME)
    local target="$1"
    local linkp="$2"

    if [ ! -e "$target" ]; then
        warn "Skip (missing): $target"
        return
    fi

    # If link already exists correctly, skip
    if [ -L "$linkp" ]; then
        local cur
        cur="$(readlink "$linkp")" || cur=""
        if [ "$cur" = "$target" ]; then
            ok "Already linked: $linkp -> $target"
            return
        fi
    fi

    # If something else exists at link path, back it up or remove
    if [ -e "$linkp" ] || [ -L "$linkp" ]; then
        backup_or_remove "$linkp"
    fi

    ensure_parent_dir "$linkp"
    if [ $DRY_RUN -eq 1 ]; then
        info "Would ln -s $target $linkp"
    else
        ln -s -- "$target" "$linkp"
        ok "Linked: $linkp -> $target"
    fi
}

ensure_zsh_shell() {
    # Check if zsh is installed
    if ! command -v zsh >/dev/null 2>&1; then
        warn "zsh not found in PATH. Install zsh first, then re-run this script."
        warn "  sudo apt-get install zsh  # or your package manager"
        return 1
    fi

    local zsh_path
    zsh_path="$(command -v zsh)"

    # Check if zsh is already the default shell
    local current_shell
    current_shell="$(getent passwd "$USER" | cut -d: -f7)"
    
    if [ "$current_shell" = "$zsh_path" ]; then
        ok "Shell already set to zsh: $zsh_path"
        return 0
    fi

    # Check if zsh is in /etc/shells
    if ! grep -qxF "$zsh_path" /etc/shells 2>/dev/null; then
        warn "zsh ($zsh_path) not listed in /etc/shells"
        if [ $DRY_RUN -eq 1 ]; then
            info "Would add: echo '$zsh_path' | sudo tee -a /etc/shells"
        else
            info "Adding zsh to /etc/shells..."
            echo "$zsh_path" | sudo tee -a /etc/shells >/dev/null
        fi
    fi

    # Change the shell
    if [ $DRY_RUN -eq 1 ]; then
        info "Would run: chsh -s $zsh_path"
        info "Note: You would need to log out and back in for the shell change to take effect"
    else
        info "🔄 Changing default shell to zsh..."
        if chsh -s "$zsh_path"; then
            ok "Default shell changed to zsh: $zsh_path"
            warn "⚠️  Log out and back in for the shell change to take effect"
        else
            err "Failed to change shell. You may need to run: chsh -s $zsh_path"
            return 1
        fi
    fi
}

# ---------- Parse args ----------
while [ $# -gt 0 ]; do
    case "$1" in
    --repo)
        REPO_ROOT="${2:-}"
        shift 2
        ;;
    --dry-run)
        DRY_RUN=1
        shift
        ;;
    --force)
        FORCE=1
        shift
        ;;
    -h | --help)
        usage
        exit 0
        ;;
    *)
        err "Unknown option: $1"
        usage
        exit 1
        ;;
    esac
done

# ---------- Resolve repo root ----------
if [ -z "${REPO_ROOT}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
    REPO_ROOT="$(abs_path "$SCRIPT_DIR/..")"
fi

CONFIG_DIR="$XDG_CONFIG_HOME_DEFAULT"
NVIM_SRC="$REPO_ROOT/nvim" # current layout
NVIM_DST="$CONFIG_DIR/nvim"
BAT_SRC="$REPO_ROOT/bat"
BAT_DST="$CONFIG_DIR/bat"
LAZYGIT_SRC="$REPO_ROOT/lazygit"
LAZYGIT_DST="$CONFIG_DIR/lazygit"
WEZTERM_SRC="$REPO_ROOT/wezterm/wezterm.lua"
WEZTERM_DST="$HOME/.wezterm.lua"
CONFIG_SRC="$REPO_ROOT/config" # future layout: repo/config/<name> → ~/.config/<name>
ZSH_SRC="$REPO_ROOT/zsh/.zshrc"
ZSH_DST="$HOME/.zshrc"
P10K_SRC="$REPO_ROOT/zsh/.p10k.zsh"
P10K_DST="$HOME/.p10k.zsh"

log "---------------------------------------------"
log "Dotfiles setup (Linux)"
log "Repo root:        $REPO_ROOT"
log "XDG_CONFIG_HOME:  $CONFIG_DIR"
if is_wsl; then log "Environment:       WSL detected"; else log "Environment:       Native Linux"; fi
[ $DRY_RUN -eq 1 ] && log "Mode:             DRY-RUN"
[ $FORCE -eq 1 ] && log "Conflict policy:  FORCE (overwrite)" || log "Conflict policy:  BACKUP"
log "---------------------------------------------"

# ---------- Link Neovim (top-level 'nvim/' layout) ----------
if [ -e "$NVIM_SRC" ]; then
    info "Linking Neovim config (top-level):"
    link_path "$NVIM_SRC" "$NVIM_DST"
fi

# ---------- Link Bat (top-level 'bat/' layout) ----------
if [ -e "$BAT_SRC" ]; then
    info "Linking Bat config (top-level):"
    link_path "$BAT_SRC" "$BAT_DST"

    # Rebuild bat cache to register the new theme
    if command -v bat >/dev/null 2>&1; then
        if [ $DRY_RUN -eq 1 ]; then
            info "Would run: bat cache --build"
        else
            info "🔄 Rebuilding bat cache..."
            bat cache --build >/dev/null 2>&1 && ok "Bat cache rebuilt" || warn "Failed to rebuild bat cache"
        fi
    else
        warn "bat not found in PATH. Install bat and run 'bat cache --build' to use the theme."
    fi
fi

# ---------- Link Delta (top-level 'delta/' layout) ----------
DELTA_SRC="$REPO_ROOT/delta"
DELTA_DST="$CONFIG_DIR/delta"
if [ -e "$DELTA_SRC" ]; then
    info "Linking Delta config (top-level):"
    link_path "$DELTA_SRC" "$DELTA_DST"
fi

# ---------- Link Lazygit (top-level 'lazygit/' layout) ----------
if [ -e "$LAZYGIT_SRC" ]; then
    info "Linking Lazygit config (top-level):"
    link_path "$LAZYGIT_SRC" "$LAZYGIT_DST"
fi

# ---------- Link WezTerm (top-level 'wezterm/' layout) ----------
if [ -e "$WEZTERM_SRC" ]; then
    info "Linking WezTerm config:"
    link_path "$WEZTERM_SRC" "$WEZTERM_DST"
fi

# ---------- Link any repo/config/* → ~/.config/<name> ----------
if [ -d "$CONFIG_SRC" ]; then
    info "Linking repo/config/* into $CONFIG_DIR"
    shopt -s nullglob dotglob
    for entry in "$CONFIG_SRC"/*; do
        name="$(basename "$entry")"
        # Only link files or directories one level deep (no recursion here)
        link_path "$entry" "$CONFIG_DIR/$name"
    done
    shopt -u nullglob dotglob
fi

# ---------- Link ~/.zshrc if present in repo ----------
if [ -f "$ZSH_SRC" ]; then
    info "Linking Zsh config:"
    link_path "$ZSH_SRC" "$ZSH_DST"
    
    # Ensure zsh is the default shell
    info "Ensuring zsh is your default shell:"
    ensure_zsh_shell
fi

# ---------- Link ~/.p10k.zsh (Powerlevel10k prompt) if present in repo ----------
if [ -f "$P10K_SRC" ]; then
    info "Linking Powerlevel10k config:"
    link_path "$P10K_SRC" "$P10K_DST"
fi

ok "Setup complete."
