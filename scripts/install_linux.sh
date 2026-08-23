#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------
# Ubuntu installer (native + WSL-aware)
# Reads packages/linux.txt where each line is:
#   apt  <pkg>
#   snap <pkg> [flags]
#   flat <app.id> [flags]
#   dev  <toolchain>
#   font <NerdFontName>
#
# Examples:
#   apt  ripgrep
#   apt  fd-find
#   snap code --classic
#   flat com.brave.Browser
#   dev  rust
#   font JetBrainsMono
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
FONT_LINES=() # each entry is a Nerd Fonts release name, e.g. JetBrainsMono
APT_SKIPPED=() # apt packages not present in any configured repo
APT_FAILED=()  # apt packages whose install command failed

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
    font) [ -n "$rest" ] && FONT_LINES+=("$rest") ;;
    *) warn "Unknown manager '$manager' in line: $raw" ;;
    esac
done <"$PKG_FILE"

# ---------- Helpers: installed checks ----------
apt_installed() {
    dpkg -s "$1" >/dev/null 2>&1
}

# Whether the package exists in any configured repo on this release. Guards the
# install loop: 'apt-get install' on an unknown package is a hard error, and
# under 'set -e' that would abort the whole bootstrap over one missing name.
apt_available() {
    apt-cache show "$1" >/dev/null 2>&1
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
    local rustup_bin="$HOME/.cargo/bin/rustup"
    [ -x "$rustup_bin" ] || rustup_bin="$(command -v rustup 2>/dev/null || true)"

    if [ -n "$rustup_bin" ] && [ -x "$rustup_bin" ]; then
        # 'rustup update' refreshes rustup itself plus every installed toolchain,
        # and is a no-op when they are already current.
        info "dev: updating rust toolchains via rustup"
        run "'$rustup_bin' update"
        ok "dev: rust $("${HOME}/.cargo/bin/rustc" --version 2>/dev/null || rustc --version 2>/dev/null)"
        return
    fi

    if command -v rustc >/dev/null 2>&1; then
        warn "dev: rustc present but not rustup-managed; leaving it alone"
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
    local have_nvm=""
    if [ -s "$NVM_DIR/nvm.sh" ]; then
        # shellcheck disable=SC1091
        have_nvm="v$(. "$NVM_DIR/nvm.sh" >/dev/null 2>&1 && nvm --version 2>/dev/null)"
    fi

    if [ "$have_nvm" = "$nvm_ver" ]; then
        ok "dev: nvm already installed ($have_nvm)"
    else
        # The install script doubles as the upgrade path; safe to re-run.
        if [ -n "$have_nvm" ] && [ "$have_nvm" != "v" ]; then
            info "dev: updating nvm ($have_nvm -> $nvm_ver)"
        else
            info "dev: installing nvm $nvm_ver"
        fi
        run "curl -fsSL 'https://raw.githubusercontent.com/nvm-sh/nvm/${nvm_ver}/install.sh' | bash"
    fi

    if [ $DRY_RUN -eq 1 ]; then
        echo "• nvm install --lts && nvm alias default 'lts/*'"
        return
    fi

    # shellcheck disable=SC1091
    . "$NVM_DIR/nvm.sh"

    # 'nvm install --lts' is a no-op when the newest LTS is already present, and
    # installs it when a new LTS line ships. Carry global packages across so an
    # LTS bump doesn't silently drop them.
    info "dev: installing/updating Node LTS via nvm"
    if nvm which default >/dev/null 2>&1; then
        nvm install --lts --reinstall-packages-from=default
    else
        nvm install --lts
    fi
    nvm alias default 'lts/*'
    ok "dev: node $(node -v 2>/dev/null) (default: $(nvm version default 2>/dev/null))"
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
    # '|| true': grep -m1 closes the pipe early, so curl exits 23 (SIGPIPE) and
    # pipefail would otherwise abort the whole script. Empty means failure.
    want="$(curl -fsSL https://api.github.com/repos/neovim/neovim/releases/latest 2>/dev/null |
        grep -m1 '"tag_name"' | sed -E 's/.*"(v[0-9.]+)".*/\1/' || true)"
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

install_lazygit() {
    local arch lg_arch want current tarball url

    # Not in the Ubuntu archive on any current release, so take the upstream
    # release binary rather than dropping the tool.
    arch="$(dpkg --print-architecture 2>/dev/null || echo amd64)" # amd64 | arm64
    case "$arch" in
    amd64) lg_arch="x86_64" ;;
    arm64) lg_arch="arm64" ;;
    *)
        warn "dev: unsupported arch '$arch' for lazygit; skipping"
        return
        ;;
    esac

    # Tag is vX.Y.Z but the asset name drops the leading 'v'.
    want="$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest 2>/dev/null |
        grep -m1 '"tag_name"' | sed -E 's/.*"v?([0-9.]+)".*/\1/' || true)"
    if [ -z "$want" ]; then
        warn "dev: could not determine latest lazygit version (offline/rate-limited?); skipping lazygit"
        return
    fi

    if command -v lazygit >/dev/null 2>&1; then
        # 'head -1': the output also ends with 'git version=X.Y.Z', which the
        # pattern would otherwise pick up alongside lazygit's own version.
        current="$(lazygit --version 2>/dev/null | grep -oE 'version=[0-9.]+' | head -1 | cut -d= -f2)"
        if [ "$current" = "$want" ]; then
            ok "dev: lazygit already installed ($current)"
            return
        fi
        info "dev: updating lazygit ($current -> $want)"
    else
        info "dev: installing lazygit $want"
    fi

    tarball="lazygit_${want}_linux_${lg_arch}.tar.gz"
    url="https://github.com/jesseduffield/lazygit/releases/download/v${want}/${tarball}"
    run "curl -fsSL '$url' -o '/tmp/${tarball}'"
    run "sudo tar -C /usr/local/bin -xzf '/tmp/${tarball}' lazygit"
    run "rm -f '/tmp/${tarball}'"
}

install_rustdesk() {
    local arch rd_arch want current deb url

    # GUI remote-desktop client; nothing to run against under WSL.
    if [ $WSL -eq 1 ]; then
        warn "dev: skipping rustdesk on WSL"
        return
    fi

    # Not in the Ubuntu archive; upstream ships .debs, so this stays
    # dpkg-managed. The plain asset is the Flutter build -- the '-sciter'
    # variants are the legacy UI and are deliberately not used here.
    arch="$(dpkg --print-architecture 2>/dev/null || echo amd64)" # amd64 | arm64
    case "$arch" in
    amd64) rd_arch="x86_64" ;;
    arm64) rd_arch="aarch64" ;;
    *)
        warn "dev: unsupported arch '$arch' for rustdesk; skipping"
        return
        ;;
    esac

    # Tags carry no leading 'v', and match the dpkg version directly.
    want="$(curl -fsSL https://api.github.com/repos/rustdesk/rustdesk/releases/latest 2>/dev/null |
        grep -m1 '"tag_name"' | sed -E 's/.*"v?([0-9.]+)".*/\1/' || true)"
    if [ -z "$want" ]; then
        warn "dev: could not determine latest rustdesk version (offline/rate-limited?); skipping rustdesk"
        return
    fi

    current="$(dpkg-query -W -f='${Version}' rustdesk 2>/dev/null || true)"
    if [ "$current" = "$want" ]; then
        ok "dev: rustdesk already installed ($current)"
        return
    fi
    if [ -n "$current" ]; then
        info "dev: updating rustdesk ($current -> $want)"
    else
        info "dev: installing rustdesk $want"
    fi

    deb="rustdesk-${want}-${rd_arch}.deb"
    url="https://github.com/rustdesk/rustdesk/releases/download/${want}/${deb}"
    run "curl -fsSL '$url' -o '/tmp/${deb}'"
    run "sudo apt-get install -y '/tmp/${deb}'"
    run "rm -f '/tmp/${deb}'"
}

install_glow() {
    local arch want current deb url

    # Also absent from the Ubuntu archive. Upstream ships a .deb, so this stays
    # dpkg-managed rather than a loose binary in /usr/local/bin.
    arch="$(dpkg --print-architecture 2>/dev/null || echo amd64)" # amd64 | arm64
    case "$arch" in
    amd64 | arm64) ;;
    *)
        warn "dev: unsupported arch '$arch' for glow; skipping"
        return
        ;;
    esac

    want="$(curl -fsSL https://api.github.com/repos/charmbracelet/glow/releases/latest 2>/dev/null |
        grep -m1 '"tag_name"' | sed -E 's/.*"v?([0-9.]+)".*/\1/' || true)"
    if [ -z "$want" ]; then
        warn "dev: could not determine latest glow version (offline/rate-limited?); skipping glow"
        return
    fi

    current="$(dpkg-query -W -f='${Version}' glow 2>/dev/null || true)"
    if [ "$current" = "$want" ]; then
        ok "dev: glow already installed ($current)"
        return
    fi
    if [ -n "$current" ]; then
        info "dev: updating glow ($current -> $want)"
    else
        info "dev: installing glow $want"
    fi

    deb="glow_${want}_${arch}.deb"
    url="https://github.com/charmbracelet/glow/releases/download/v${want}/${deb}"
    run "curl -fsSL '$url' -o '/tmp/${deb}'"
    run "sudo apt-get install -y '/tmp/${deb}'"
    run "rm -f '/tmp/${deb}'"
}

install_wezterm() {
    local arch ubuntu_ver deb url sha_url want_sha stamp_dir stamp tmp new_ver cur_ver

    # A GUI terminal inside WSL is pointless: the Windows-side WezTerm already
    # attaches to this distro via its launch_menu entry.
    if [ $WSL -eq 1 ]; then
        warn "dev: skipping wezterm on WSL (use the Windows WezTerm; see wezterm/wezterm.lua)"
        return
    fi

    # Upstream's last stable tag is 20240203 (Feb 2024) and the apt repo still
    # serves it, so 'nightly' is the only live channel -- it rebuilds daily.
    # WezTerm is absent from the Ubuntu archive entirely, and the Flatpak build
    # is sandboxed, so a .deb straight from the release is the way in.
    arch="$(dpkg --print-architecture 2>/dev/null || echo amd64)" # amd64 | arm64
    ubuntu_ver="$(. /etc/os-release 2>/dev/null && printf "%s" "${VERSION_ID:-}")"

    if [ "$arch" = "arm64" ]; then
        deb="wezterm-nightly.Ubuntu${ubuntu_ver}.arm64.deb"
    else
        deb="wezterm-nightly.Ubuntu${ubuntu_ver}.deb"
    fi
    url="https://github.com/wezterm/wezterm/releases/download/nightly/${deb}"

    # Prefer the build matching this release; fall back to the 22.04 one, whose
    # deps (libc6 >= 2.35, libssl3) resolve on anything newer.
    if ! curl -fsSLI "$url" >/dev/null 2>&1; then
        if [ "$arch" = "arm64" ]; then
            deb="wezterm-nightly.Ubuntu22.04.arm64.deb"
        else
            deb="wezterm-nightly.Ubuntu22.04.deb"
        fi
        url="https://github.com/wezterm/wezterm/releases/download/nightly/${deb}"
        if ! curl -fsSLI "$url" >/dev/null 2>&1; then
            warn "dev: no wezterm nightly build for Ubuntu ${ubuntu_ver} ($arch); skipping wezterm"
            return
        fi
        warn "dev: no wezterm build for Ubuntu ${ubuntu_ver}; using the 22.04 one"
    fi

    # The rolling 'nightly' tag carries no version in the URL, so compare the
    # checksum sidecar against a stamp to avoid re-downloading ~36MB every run.
    # arm64 debs ship without a .sha256, hence the empty-want_sha path below.
    sha_url="${url}.sha256"
    want_sha="$(curl -fsSL "$sha_url" 2>/dev/null | awk '{print $1}')"
    stamp_dir="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
    stamp="$stamp_dir/wezterm-nightly.sha256"

    if command -v wezterm >/dev/null 2>&1 && [ -n "$want_sha" ] && [ -f "$stamp" ] &&
        [ "$(cat "$stamp")" = "$want_sha" ]; then
        ok "dev: wezterm already up to date ($(wezterm --version 2>/dev/null))"
        return
    fi

    if [ $DRY_RUN -eq 1 ]; then
        echo "• curl -fsSL '$url' -o '/tmp/${deb}'"
        echo "• sudo apt-get install -y '/tmp/${deb}'"
        return
    fi

    info "dev: fetching wezterm nightly ($deb)"
    tmp="/tmp/${deb}"
    if ! curl -fsSL "$url" -o "$tmp"; then
        warn "dev: wezterm download failed (offline?); skipping wezterm"
        return
    fi

    if [ -n "$want_sha" ] && ! printf "%s  %s\n" "$want_sha" "$tmp" | sha256sum -c - >/dev/null 2>&1; then
        err "dev: wezterm checksum mismatch for $deb; refusing to install"
        rm -f "$tmp"
        return
    fi

    new_ver="$(dpkg-deb -f "$tmp" Version 2>/dev/null)"
    cur_ver="$(dpkg-query -W -f='${Version}' wezterm-nightly 2>/dev/null || true)"
    if [ -n "$new_ver" ] && [ "$new_ver" = "$cur_ver" ]; then
        ok "dev: wezterm already installed ($cur_ver)"
        mkdir -p "$stamp_dir" && printf "%s\n" "$want_sha" >"$stamp"
        rm -f "$tmp"
        return
    fi

    # wezterm-nightly declares Conflicts: wezterm, so the frozen stable package
    # has to go first if it was ever installed.
    if dpkg -s wezterm >/dev/null 2>&1; then
        info "dev: removing stale stable wezterm (replaced by nightly)"
        sudo apt-get remove -y wezterm
    fi

    if [ -n "$cur_ver" ]; then
        info "dev: updating wezterm ($cur_ver -> $new_ver)"
    else
        info "dev: installing wezterm $new_ver"
    fi
    sudo apt-get install -y "$tmp"
    mkdir -p "$stamp_dir" && printf "%s\n" "$want_sha" >"$stamp"
    rm -f "$tmp"
}

# ---------- Nerd Font installer (idempotent) ----------
# Installs per-user into ~/.local/share/fonts so no sudo is needed. Only the
# non-Mono "<Name> Nerd Font" faces are unpacked; those TTFs register under both
# "JetBrainsMono Nerd Font" and the short "JetBrainsMono NF" alias that
# wezterm/wezterm.lua asks for.
install_nerdfont() {
    local name want current font_dir stamp tarball url

    # Fonts are a GUI concern; under WSL the Windows host terminal supplies them.
    if [ $WSL -eq 1 ]; then
        warn "font: skipping $1 on WSL (install it on the Windows side instead)"
        return
    fi

    name="$1"
    # '|| true' for the same SIGPIPE reason as install_neovim above.
    want="$(curl -fsSL https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest 2>/dev/null |
        grep -m1 '"tag_name"' | sed -E 's/.*"(v[0-9.]+)".*/\1/' || true)"
    if [ -z "$want" ]; then
        warn "font: could not determine latest Nerd Fonts version (offline/rate-limited?); skipping $name"
        return
    fi

    font_dir="${XDG_DATA_HOME:-$HOME/.local/share}/fonts/NerdFonts/$name"
    stamp="$font_dir/.nerd-fonts-version"
    if [ -f "$stamp" ]; then
        current="$(cat "$stamp")"
        if [ "$current" = "$want" ]; then
            ok "font: $name Nerd Font already installed ($current)"
            return
        fi
        info "font: updating $name Nerd Font ($current -> $want)"
    else
        info "font: installing $name Nerd Font $want"
    fi

    tarball="${name}.tar.xz"
    url="https://github.com/ryanoasis/nerd-fonts/releases/download/${want}/${tarball}"
    run "curl -fsSL '$url' -o '/tmp/${tarball}'"
    run "rm -rf '$font_dir'"
    run "mkdir -p '$font_dir'"
    # The trailing '-' anchors this to the plain NF faces, excluding the
    # NerdFontMono / NerdFontPropo / NL variants in the same archive.
    run "tar -C '$font_dir' -xJf '/tmp/${tarball}' --wildcards '${name}NerdFont-*.ttf'"
    run "rm -f '/tmp/${tarball}'"
    run "printf '%s\\n' '$want' >'$stamp'"
    run "fc-cache -f '$font_dir'"
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
        elif ! apt_available "$pkg"; then
            warn "apt: $pkg not available on this release; skipping"
            APT_SKIPPED+=("$pkg")
        else
            info "apt: installing $pkg"
            # Non-fatal: a single bad package must not strand the dev/font steps.
            if ! run "sudo apt-get install -y '$pkg'"; then
                warn "apt: $pkg failed to install; continuing"
                APT_FAILED+=("$pkg")
            fi
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
        wezterm) install_wezterm ;;
        lazygit) install_lazygit ;;
        glow) install_glow ;;
        rustdesk) install_rustdesk ;;
        *) warn "Unknown dev tool '$tool' in line: dev $line" ;;
        esac
    done
    warn "Dev toolchains: open a new shell (or 'source ~/.zshrc') to pick up PATH changes."
fi

# ---------- FONTS ----------
if [ "${#FONT_LINES[@]}" -gt 0 ]; then
    info "Setting up fonts..."
    for line in "${FONT_LINES[@]}"; do
        install_nerdfont "$(printf "%s" "$line" | awk '{print $1}')"
    done
fi

if [ "${#APT_SKIPPED[@]}" -gt 0 ]; then
    warn "Unavailable on this release, not installed: ${APT_SKIPPED[*]}"
fi
if [ "${#APT_FAILED[@]}" -gt 0 ]; then
    warn "Failed to install: ${APT_FAILED[*]}"
fi

ok "Install complete."
