#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------
# Ubuntu installer (native + WSL-aware)
# Reads packages/linux.txt where each line is:
#   apt  <pkg>
#   snap <pkg> [flags]
#   flat <app.id> [flags]
#
# Examples:
#   apt  ripgrep
#   apt  fd-find
#   snap code --classic
#   flat com.brave.Browser
#
# Safe to re-run. Skips already-installed packages.
# -------------------------------------------------------

DRY_RUN=0
REPO_ROOT=""
PKG_FILE_DEFAULT="packages/linux.txt"

usage() {
    cat <<EOF
Usage: $0 [--repo PATH] [--dry-run]

Options:
  --repo PATH   Path to repo root (defaults to parent of this script)
  --dry-run     Show actions without changing anything

Reads: packages/linux.txt under the repo root.
EOF
}

log() { printf "%s\n" "$*"; }
info() { printf "🔧 %s\n" "$*"; }
ok() { printf "✅ %s\n" "$*"; }
warn() { printf "⚠️  %s\n" "$*" >&2; }
err() { printf "❌ %s\n" "$*" >&2; }

is_wsl() { grep -qi microsoft /proc/version 2>/dev/null; }

abs_path() {
    local p="$1"
    if [ -d "$p" ]; then (cd "$p" && pwd -P); else (cd "$(dirname "$p")" && printf "%s/%s\n" "$(pwd -P)" "$(basename "$p")"); fi
}

run() {
    # Executes unless dry-run
    if [ "$DRY_RUN" -eq 1 ]; then
        printf "• %s\n" "$*"
    else
        eval "$@"
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

# ---------- Resolve repo root & package file ----------
if [ -z "${REPO_ROOT}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
    REPO_ROOT="$(abs_path "$SCRIPT_DIR/..")"
fi
PKG_FILE="$REPO_ROOT/$PKG_FILE_DEFAULT"

if [ ! -f "$PKG_FILE" ]; then
    err "Package list not found: $PKG_FILE"
    exit 1
fi

WSL=0
if is_wsl; then WSL=1; fi

log "---------------------------------------------"
log "Ubuntu installer"
log "Repo:   $REPO_ROOT"
log "List:   $PKG_FILE"
[ $WSL -eq 1 ] && log "Env:    WSL detected (snap/flatpak will be skipped)" || log "Env:    Native Ubuntu"
[ $DRY_RUN -eq 1 ] && log "Mode:   DRY RUN"
log "---------------------------------------------"

# ---------- Collect package lines ----------
APT_PKGS=()
SNAP_LINES=() # each entry is full "pkg [flags]"
FLAT_LINES=() # each entry is full "app.id [flags]"
DEV_LINES=()  # each entry is a toolchain name: rust | go | node

# Strip comments and blank lines; keep manager + remainder
while IFS= read -r raw; do
    # remove inline comments: everything after an unescaped '#'
    line="${raw%%#*}"
    line="$(printf "%s" "$line" | sed 's/[[:space:]]\+$//')"
    [ -z "$line" ] && continue

    manager="$(printf "%s" "$line" | awk '{print $1}')"
    rest="$(printf "%s" "$line" | cut -d' ' -f2-)"
    [ -z "$manager" ] && continue

    case "$manager" in
    apt) [ -n "$rest" ] && APT_PKGS+=("$rest") ;;
    snap) [ -n "$rest" ] && SNAP_LINES+=("$rest") ;;
    flat) [ -n "$rest" ] && FLAT_LINES+=("$rest") ;;
    dev) [ -n "$rest" ] && DEV_LINES+=("$rest") ;;
    *) warn "Unknown manager '$manager' in line: $raw" ;;
    esac
done <"$PKG_FILE"

# ---------- Helpers: installed checks ----------
apt_installed() {
    dpkg -s "$1" >/dev/null 2>&1
}

snap_installed() {
    # snap list exits 0 if installed, 2 otherwise
    snap list "$1" >/dev/null 2>&1
}

flat_installed() {
    flatpak info "$1" >/dev/null 2>&1
}

# ---------- Dev toolchain installers (idempotent) ----------
# These use the canonical upstream installers rather than apt so the versions
# stay current and self-updating. PATH wiring is handled in zsh/.zshrc.
install_rust() {
    if command -v rustc >/dev/null 2>&1 || [ -x "$HOME/.cargo/bin/rustc" ]; then
        ok "dev: rust already installed ($("${HOME}/.cargo/bin/rustc" --version 2>/dev/null || rustc --version 2>/dev/null))"
        return
    fi
    info "dev: installing rust via rustup"
    # --no-modify-path: shell PATH is managed by zsh/.zshrc (sources ~/.cargo/env)
    run "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path"
}

install_go() {
    local arch want current tarball url
    arch="$(dpkg --print-architecture 2>/dev/null || echo amd64)" # amd64 | arm64
    want="$(curl -fsSL 'https://go.dev/VERSION?m=text' 2>/dev/null | head -1)" # e.g. go1.26.4
    if [ -z "$want" ]; then
        warn "dev: could not determine latest Go version (offline?); skipping go"
        return
    fi
    if [ -x /usr/local/go/bin/go ]; then
        current="$(/usr/local/go/bin/go version | awk '{print $3}')"
        if [ "$current" = "$want" ]; then
            ok "dev: go already installed ($current)"
            return
        fi
        info "dev: updating go ($current -> $want)"
    else
        info "dev: installing go $want"
    fi
    tarball="${want}.linux-${arch}.tar.gz"
    url="https://go.dev/dl/${tarball}"
    run "curl -fsSL '$url' -o '/tmp/${tarball}'"
    run "sudo rm -rf /usr/local/go"
    run "sudo tar -C /usr/local -xzf '/tmp/${tarball}'"
    run "rm -f '/tmp/${tarball}'"
}

install_node() {
    local nvm_ver="v0.40.5"
    export NVM_DIR="$HOME/.nvm"
    if [ -s "$NVM_DIR/nvm.sh" ]; then
        ok "dev: nvm already installed"
    else
        info "dev: installing nvm $nvm_ver"
        run "curl -fsSL 'https://raw.githubusercontent.com/nvm-sh/nvm/${nvm_ver}/install.sh' | bash"
    fi
    if [ $DRY_RUN -eq 1 ]; then
        echo "• nvm install --lts && nvm alias default 'lts/*'"
        return
    fi
    # shellcheck disable=SC1091
    . "$NVM_DIR/nvm.sh"
    if nvm which default >/dev/null 2>&1; then
        ok "dev: node already installed ($(node -v 2>/dev/null))"
    else
        info "dev: installing Node LTS via nvm"
        nvm install --lts
        nvm alias default 'lts/*'
    fi
}

install_neovim() {
    local arch nvim_arch want current tarball url
    arch="$(dpkg --print-architecture 2>/dev/null || echo amd64)" # amd64 | arm64
    case "$arch" in
    amd64) nvim_arch="x86_64" ;;
    arm64) nvim_arch="arm64" ;;
    *)
        warn "dev: unsupported arch '$arch' for neovim; skipping"
        return
        ;;
    esac

    # Latest stable release tag, e.g. v0.12.3 (excludes nightly/prereleases).
    want="$(curl -fsSL https://api.github.com/repos/neovim/neovim/releases/latest 2>/dev/null |
        grep -m1 '"tag_name"' | sed -E 's/.*"(v[0-9.]+)".*/\1/')"
    if [ -z "$want" ]; then
        warn "dev: could not determine latest Neovim version (offline/rate-limited?); skipping neovim"
        return
    fi

    # Drop the apt-managed neovim so there's a single, current copy on PATH.
    if dpkg -s neovim >/dev/null 2>&1; then
        info "dev: removing apt-managed neovim (replaced by upstream tarball)"
        run "sudo apt-get remove -y neovim"
    fi

    if [ -x /opt/nvim/bin/nvim ]; then
        current="$(/opt/nvim/bin/nvim --version | head -1 | awk '{print $2}')" # vX.Y.Z
        if [ "$current" = "$want" ]; then
            ok "dev: neovim already installed ($current)"
            return
        fi
        info "dev: updating neovim ($current -> $want)"
    else
        info "dev: installing neovim $want"
    fi

    tarball="nvim-linux-${nvim_arch}.tar.gz"
    url="https://github.com/neovim/neovim/releases/download/${want}/${tarball}"
    run "curl -fsSL '$url' -o '/tmp/${tarball}'"
    run "sudo rm -rf /opt/nvim '/opt/nvim-linux-${nvim_arch}'"
    run "sudo tar -C /opt -xzf '/tmp/${tarball}'"
    run "sudo mv '/opt/nvim-linux-${nvim_arch}' /opt/nvim"
    run "sudo ln -sf /opt/nvim/bin/nvim /usr/local/bin/nvim"
    run "rm -f '/tmp/${tarball}'"
}

install_claude() {
    if command -v claude >/dev/null 2>&1 || [ -x "$HOME/.local/bin/claude" ]; then
        ok "dev: claude already installed ($("${HOME}/.local/bin/claude" --version 2>/dev/null || claude --version 2>/dev/null))"
        return
    fi
    info "dev: installing Claude Code via official installer"
    run "curl -fsSL https://claude.ai/install.sh | bash"
}

# ---------- APT installs ----------
if [ "${#APT_PKGS[@]}" -gt 0 ]; then
    info "Preparing apt..."
    if [ $DRY_RUN -eq 0 ]; then
        sudo apt-get update -y
    else
        echo "• sudo apt-get update -y"
    fi

    for pkg in "${APT_PKGS[@]}"; do
        if apt_installed "$pkg"; then
            ok "apt: $pkg already installed"
        else
            info "apt: installing $pkg"
            run "sudo apt-get install -y '$pkg'"
        fi
    done
fi

# ---------- SNAP installs ----------
if [ "${#SNAP_LINES[@]}" -gt 0 ]; then
    if [ $WSL -eq 1 ]; then
        warn "Skipping snap packages on WSL:"
        for s in "${SNAP_LINES[@]}"; do
            warn "  snap $s"
        done
    else
        if ! command -v snap >/dev/null 2>&1; then
            info "snapd not found; installing snapd"
            run "sudo apt-get install -y snapd"
            warn "If this is your first snapd install, you may need to log out/in or reboot."
        fi

        for line in "${SNAP_LINES[@]}"; do
            # First token is the package name; rest are flags (e.g., --classic)
            snap_pkg="$(printf "%s" "$line" | awk '{print $1}')"
            snap_flags="$(printf "%s" "$line" | cut -s -d' ' -f2-)"
            if snap_installed "$snap_pkg"; then
                ok "snap: $snap_pkg already installed"
            else
                info "snap: installing $snap_pkg ${snap_flags}"
                if [ -n "$snap_flags" ]; then
                    run "sudo snap install '$snap_pkg' $snap_flags"
                else
                    run "sudo snap install '$snap_pkg'"
                fi
            fi
        done
    fi
fi

# ---------- FLATPAK installs ----------
if [ "${#FLAT_LINES[@]}" -gt 0 ]; then
    if [ $WSL -eq 1 ]; then
        warn "Skipping flatpak apps on WSL:"
        for f in "${FLAT_LINES[@]}"; do
            warn "  flat $f"
        done
    else
        if ! command -v flatpak >/dev/null 2>&1; then
            info "flatpak not found; installing flatpak"
            run "sudo apt-get install -y flatpak"
        fi
        # Ensure Flathub remote
        if [ $DRY_RUN -eq 1 ]; then
            echo "• flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo"
        else
            flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo >/dev/null || true
        fi

        for line in "${FLAT_LINES[@]}"; do
            flat_id="$(printf "%s" "$line" | awk '{print $1}')"
            flat_flags="$(printf "%s" "$line" | cut -s -d' ' -f2-)"
            if flat_installed "$flat_id"; then
                ok "flat: $flat_id already installed"
            else
                info "flat: installing $flat_id ${flat_flags}"
                if [ -n "$flat_flags" ]; then
                    run "flatpak install -y flathub '$flat_id' $flat_flags"
                else
                    run "flatpak install -y flathub '$flat_id'"
                fi
            fi
        done
    fi
fi

# ---------- DEV toolchains ----------
if [ "${#DEV_LINES[@]}" -gt 0 ]; then
    info "Setting up developer toolchains..."
    for line in "${DEV_LINES[@]}"; do
        tool="$(printf "%s" "$line" | awk '{print $1}')"
        case "$tool" in
        rust) install_rust ;;
        go) install_go ;;
        node) install_node ;;
        neovim) install_neovim ;;
        claude) install_claude ;;
        *) warn "Unknown dev tool '$tool' in line: dev $line" ;;
        esac
    done
    warn "Dev toolchains: open a new shell (or 'source ~/.zshrc') to pick up PATH changes."
fi

ok "Install complete."
