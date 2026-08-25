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
#   repo <name> url=<URI> suite=<s> comps=<c> key=<keyurl> [arch=<arch>]
#   pin  <name> pkg=<glob> priority=<n> [origin=<host>] [release=<expr>]
#   ppa  <owner/name>
#
# Examples:
#   apt  ripgrep
#   apt  fd-find
#   snap code --classic
#   flat com.brave.Browser
#   dev  rust
#   font JetBrainsMono
#   repo brave url=https://brave-browser-apt-release.s3.brave.com/ suite=stable comps=main key=https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
#   pin  mozilla pkg=* origin=packages.mozilla.org priority=1000
#   ppa  dotnet/backports
#
# repo/pin/ppa entries are applied before any apt install, so an 'apt <pkg>'
# line may depend on a repo declared here. 'pin' writes preferences.d files and
# is what decides which repo wins when the same package exists in several.
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
CARGO_LINES=() # each entry is "crate [extra cargo-install flags]"
FONT_LINES=() # each entry is a Nerd Fonts release name, e.g. JetBrainsMono
REPO_LINES=() # each entry is "name key=val key=val ..." for a third-party apt repo
PPA_LINES=()  # each entry is a Launchpad PPA, e.g. dotnet/backports
PIN_LINES=()  # each entry is "name key=val ..." for an apt preferences.d pin
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
    cargo) [ -n "$rest" ] && CARGO_LINES+=("$rest") ;;
    font) [ -n "$rest" ] && FONT_LINES+=("$rest") ;;
    repo) [ -n "$rest" ] && REPO_LINES+=("$rest") ;;
    pin) [ -n "$rest" ] && PIN_LINES+=("$rest") ;;
    ppa) [ -n "$rest" ] && PPA_LINES+=("$rest") ;;
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

# The version apt would install right now.
apt_candidate() {
    apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/{print $2}'
}

# True when an explicit pin (priority >= 1000) selects a version other than the
# one already installed. Without this an 'apt <pkg>' line is a no-op as soon as
# *any* build of the package is present -- wrong for firefox, where Ubuntu
# preinstalls a stub whose only job is to reinstall the snap.
apt_pin_switch() {
    local pol inst cand prio
    pol="$(apt-cache policy "$1" 2>/dev/null)" || return 1
    inst="$(printf "%s" "$pol" | awk '/Installed:/{print $2}')"
    cand="$(printf "%s" "$pol" | awk '/Candidate:/{print $2}')"
    if [ -z "$cand" ] || [ "$cand" = "(none)" ] || [ "$inst" = "(none)" ] ||
        [ "$inst" = "$cand" ]; then
        return 1
    fi
    # Priority of the candidate's own row in the version table. Scanning must
    # start below 'Version table:' -- the 'Candidate: <ver>' header also holds a
    # field equal to $cand, and matching that yields an empty priority.
    prio="$(printf "%s" "$pol" | awk -v c="$cand" '
        /Version table:/ { t = 1; next }
        t && NF >= 2 && $(NF - 1) == c && $NF ~ /^-?[0-9]+$/ { print $NF; exit }')"
    case "$prio" in '' | *[!0-9-]*) return 1 ;; esac
    [ "$prio" -ge 1000 ]
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
# Any words after 'rust' on the dev line are extra rustup targets, e.g.
# 'dev rust wasm32-unknown-unknown'. The host target is implicit and never
# needs naming.
install_rust() {
    local targets="${1:-}"
    local target
    local rustup_bin="$HOME/.cargo/bin/rustup"
    [ -x "$rustup_bin" ] || rustup_bin="$(command -v rustup 2>/dev/null || true)"

    if [ -n "$rustup_bin" ] && [ -x "$rustup_bin" ]; then
        # 'rustup update' refreshes rustup itself plus every installed toolchain,
        # and is a no-op when they are already current.
        info "dev: updating rust toolchains via rustup"
        run "'$rustup_bin' update"
        ok "dev: rust $("${HOME}/.cargo/bin/rustc" --version 2>/dev/null || rustc --version 2>/dev/null)"
    elif command -v rustc >/dev/null 2>&1; then
        # No rustup to add a target with either, so there is nothing further to
        # do here even if the line names some.
        warn "dev: rustc present but not rustup-managed; leaving it alone"
        return
    else
        info "dev: installing rust via rustup"
        # --no-modify-path: shell PATH is managed by zsh/.zshrc (sources ~/.cargo/env)
        run "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path"
        rustup_bin="$HOME/.cargo/bin/rustup"
    fi

    # 'rustup target add' is already idempotent, but it goes to the network to
    # find that out, so ask the local list first.
    for target in $targets; do
        if "$rustup_bin" target list --installed 2>/dev/null | grep -qx "$target"; then
            ok "dev: rust target $target already installed"
        else
            info "dev: adding rust target $target"
            run "'$rustup_bin' target add '$target'"
        fi
    done
}

# A crates.io binary, e.g. 'cargo trunk'. --locked is the point: without it
# cargo re-resolves the crate's dependency tree against today's registry, so one
# version number builds differently on two machines a week apart.
#
# Never reinstalled once present. These compile from source and take minutes,
# and none of them self-updates, so an installer re-run is the wrong place to
# discover a new release -- 'cargo install --force <crate>' is the right one.
install_cargo_crate() {
    local line="$1"
    local crate flags cargo_bin
    crate="$(printf "%s" "$line" | awk '{print $1}')"
    flags="$(printf "%s" "$line" | cut -s -d' ' -f2-)"

    cargo_bin="$HOME/.cargo/bin/cargo"
    [ -x "$cargo_bin" ] || cargo_bin="$(command -v cargo 2>/dev/null || true)"
    if [ -z "$cargo_bin" ] || [ ! -x "$cargo_bin" ]; then
        warn "cargo: no cargo found; skipping '$crate' (needs a 'dev rust' line above)"
        return
    fi

    # 'cargo install --list' rather than 'command -v', because a crate's binary
    # need not share its name and several crates ship more than one.
    if "$cargo_bin" install --list 2>/dev/null | grep -q "^${crate} v"; then
        ok "cargo: $crate already installed"
        return
    fi

    info "cargo: installing $crate (compiles from source; this is slow)"
    run "'$cargo_bin' install --locked $crate $flags"
}

# The three tools cargo-xwin needs to cross-compile a Windows MSVC binary, none
# of which is reachable by the name it looks for on a stock Ubuntu:
#
#   clang-cl   not packaged at all -- and does not need to be. clang picks its
#              driver mode from the name it was invoked as, so a symlink called
#              clang-cl *is* clang-cl.
#   llvm-lib   } shipped by llvm-N, but only under /usr/lib/llvm-N/bin, which
#   llvm-rc    } is not on PATH. Only the versioned names are exposed.
#
# Symptom without them, and it names none of this: cargo-xwin sets
# AR_x86_64_pc_windows_msvc=llvm-lib and the build dies partway through as
# `error occurred in cc-rs: failed to find tool "llvm-lib"`.
#
# Into ~/.local/bin rather than /usr/local/bin: it is already on PATH (see
# zsh/.zshrc) and needs no sudo. Symlinks rather than copies, so an LLVM
# upgrade under the same prefix is picked up for free.
install_msvc_cross() {
    local llvm_bin tool
    # Version-sorted, or llvm-9 would beat llvm-18.
    llvm_bin="$(find /usr/lib -maxdepth 1 -type d -name 'llvm-*' 2>/dev/null | sort -V | tail -1)"
    llvm_bin="${llvm_bin}/bin"

    if [ ! -x "$llvm_bin/clang" ]; then
        warn "dev: no clang under /usr/lib/llvm-*/bin; skipping msvc-cross (needs 'apt clang')"
        return
    fi

    run "mkdir -p '$HOME/.local/bin'"
    run "ln -sfn '$llvm_bin/clang' '$HOME/.local/bin/clang-cl'"
    for tool in llvm-lib llvm-rc; do
        if [ -e "$llvm_bin/$tool" ]; then
            run "ln -sfn '$llvm_bin/$tool' '$HOME/.local/bin/$tool'"
        else
            warn "dev: $llvm_bin/$tool is missing; cargo-xwin will fail to link"
        fi
    done
    # lld-link is the one that does come from a package (apt lld), so it is only
    # worth saying something when it is absent.
    command -v lld-link >/dev/null 2>&1 || warn "dev: no lld-link on PATH (needs 'apt lld')"
    [ "$DRY_RUN" -eq 1 ] || ok "dev: msvc-cross tools linked from $llvm_bin into ~/.local/bin"
}

# Google's Android SDK, into ~/Android/Sdk: the command-line tools first, then
# the `android` CLI they carry for the platform, the build tools, platform-tools
# (that is `adb`) and the NDK. Android Studio is the usual way to get all of this and is not
# needed for any of it -- the build loop is entirely command line -- and nothing
# else packages it: Ubuntu's own `android-sdk` trails several platform releases
# and ships no NDK at all.
#
# The NDK version is pinned rather than tracked, and it is the one number here
# worth arguing about. It has to match what a project builds against on every
# other machine, or the same source is compiled by two toolchains and a link
# error on one of them cannot be reproduced on the other. OBERTH's README sets
# 28.2.13676358 on Windows; that is where this figure comes from and it does not
# move on its own.
#
# The command-line tools themselves *are* tracked, install_go-style. Google
# publishes repository2-3.xml, which names the current revision of
# `cmdline-tools;latest` and the archive carrying it, so "latest" means here what
# it means on their download page rather than a build number going stale in this
# file.
#
# Two layout traps, and neither says what it is. The zip unpacks to a directory
# called `cmdline-tools`, and where it has to end up is `cmdline-tools/latest`:
# left as the archive writes it, the tools die with "Could not determine SDK
# root", naming neither the directory nor the reason. They work that root out from
# their own path -- two levels above `bin/` -- which is also why nothing here
# exports ANDROID_HOME to tell them: the shell does that for everything
# downstream, and this runs before there is a shell that has read it.
#
# **The packages are installed with `android sdk install`, not with
# `sdkmanager`.** Every guide on the internet says sdkmanager, and it still
# works, and as of command-line tools 23.0 it is a shim: it prints a deprecation
# notice, downloads a *second* binary (the `android` CLI) on first use, unpacks
# it, shows Google's terms, and only then does the thing asked of it. It also
# answers `--licenses` with "no longer needed", so the incantation every guide
# pairs it with is now a no-op. Going through the shim buys a warning on every
# run and an interface that is scheduled to be removed; the `android` CLI beside
# it in the same bin/ is what it forwards to.
#
# The package names differ between the two and the new spelling is the better
# one: `platforms/android-36` where sdkmanager wanted `platforms;android-36`, so
# a package name *is* its directory under the SDK root, which is what makes the
# already-installed check below a plain `-d` test rather than a network query.
install_android_sdk() {
    local sdk="$HOME/Android/Sdk"
    local ndk_version="28.2.13676358"
    local manifest="https://dl.google.com/android/repository/repository2-3.xml"
    local jdk="/usr/lib/jvm/java-17-openjdk-amd64"
    local want zip current android pkg
    local missing=()

    # The SDK tools are Java programs, so they need a JVM before they can install
    # anything. JDK 17 by preference rather than by requirement: it is the
    # version the Gradle half is pinned to, and running both halves on one JDK is
    # one less difference between them.
    if [ -x "$jdk/bin/java" ]; then
        export JAVA_HOME="$jdk"
    elif command -v java >/dev/null 2>&1; then
        warn "dev: no JDK 17 at $jdk; running the SDK tools on the default java (wants 'apt openjdk-17-jdk')"
    else
        warn "dev: no java on this machine; skipping android-sdk (needs 'apt openjdk-17-jdk')"
        return
    fi

    read -r want zip <<<"$(curl -fsSL "$manifest" 2>/dev/null | awk '
        /<remotePackage path="cmdline-tools;latest">/ { f = 1 }
        f && /<major>/ { maj = $0; gsub(/[^0-9]/, "", maj) }
        f && /<minor>/ { min = $0; gsub(/[^0-9]/, "", min) }
        f && /commandlinetools-linux-/ {
            url = $0; sub(/.*<url>/, "", url); sub(/<\/url>.*/, "", url)
            print maj "." min " " url
            exit
        }')"
    if [ -z "${want:-}" ] || [ -z "${zip:-}" ]; then
        warn "dev: could not read the Android SDK manifest (offline?); skipping android-sdk"
        return
    fi

    # Pkg.Revision in source.properties is what the installed copy calls itself,
    # and it is the same "23.0" the manifest names, so the two compare directly.
    current=""
    if [ -x "$sdk/cmdline-tools/latest/bin/android" ]; then
        current="$(sed -n 's/^Pkg\.Revision=//p' "$sdk/cmdline-tools/latest/source.properties" 2>/dev/null)"
    fi

    if [ "$current" = "$want" ]; then
        ok "dev: android command-line tools already installed ($current)"
    else
        [ -n "$current" ] && info "dev: updating android command-line tools ($current -> $want)" ||
            info "dev: installing android command-line tools $want"
        run "rm -rf '/tmp/android-cmdline-tools'"
        run "curl -fsSL 'https://dl.google.com/android/repository/$zip' -o '/tmp/$zip'"
        run "mkdir -p '/tmp/android-cmdline-tools' '$sdk/cmdline-tools'"
        run "unzip -q '/tmp/$zip' -d '/tmp/android-cmdline-tools'"
        run "rm -rf '$sdk/cmdline-tools/latest'"
        run "mv '/tmp/android-cmdline-tools/cmdline-tools' '$sdk/cmdline-tools/latest'"
        run "rm -rf '/tmp/android-cmdline-tools' '/tmp/$zip'"
    fi

    android="$sdk/cmdline-tools/latest/bin/android"
    if [ "$DRY_RUN" -eq 0 ] && [ ! -x "$android" ]; then
        warn "dev: no android CLI at $android after unpacking; skipping the SDK packages"
        return
    fi

    # Asked of the filesystem rather than of `android sdk list`, which is a
    # network round trip to answer a question the directory layout already
    # answers: a package's name is its path under the SDK root.
    for pkg in "platform-tools" "platforms/android-36" "build-tools/36.0.0" "ndk/$ndk_version"; do
        if [ -d "$sdk/$pkg" ]; then
            ok "dev: android sdk '$pkg' already installed"
        else
            missing+=("$pkg")
        fi
    done

    if [ "${#missing[@]}" -gt 0 ]; then
        info "dev: android sdk: installing ${missing[*]} (the NDK alone is some 2.5 GB)"
        # Google's SDK terms are printed on the first run and accepted by running
        # this at all; there is no non-interactive path that does not, and the
        # `--licenses` dance the old tool wanted is gone. Note the same first run
        # also states that the CLI reports usage data (commands, sub-commands and
        # flags) and names `--no-metrics` as the way out, and that flag is
        # rejected by both `android sdk install` and `android sdk list` in 23.0:
        # it is documented and not implemented, so there is currently nothing to
        # pass.
        run "'$android' sdk install $(printf "'%s' " "${missing[@]}")"
    fi

    [ "$DRY_RUN" -eq 1 ] || ok "dev: android sdk at $sdk (ndk $ndk_version)"
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

install_chrome() {
    local arch deb url

    if [ $WSL -eq 1 ]; then
        warn "dev: skipping google-chrome on WSL (use the Windows browser)"
        return
    fi

    # Deliberately not a 'repo' entry: the chrome package ships
    # /etc/cron.daily/google-chrome, which rewrites its own .sources file.
    # Declaring the repo here as well would leave two entries fighting over it.
    # Installing the .deb once is enough -- Google's repo then keeps it current
    # through ordinary apt upgrades.
    if dpkg -s google-chrome-stable >/dev/null 2>&1; then
        ok "dev: google-chrome already installed ($(dpkg-query -W -f='${Version}' google-chrome-stable 2>/dev/null)); updates come from Google's own repo"
        return
    fi

    arch="$(dpkg --print-architecture 2>/dev/null || echo amd64)"
    if [ "$arch" != "amd64" ]; then
        warn "dev: google ships no linux .deb for '$arch'; skipping google-chrome"
        return
    fi

    info "dev: installing google-chrome"
    deb="google-chrome-stable_current_amd64.deb"
    url="https://dl.google.com/linux/direct/${deb}"
    run "curl -fsSL '$url' -o '/tmp/${deb}'"
    run "sudo apt-get install -y '/tmp/${deb}'"
    run "rm -f '/tmp/${deb}'"
}

install_difftastic() {
    local arch dt_arch want current tarball url
    arch="$(dpkg --print-architecture 2>/dev/null || echo amd64)" # amd64 | arm64
    case "$arch" in
    amd64) dt_arch="x86_64" ;;
    arm64) dt_arch="aarch64" ;;
    *)
        warn "dev: unsupported arch '$arch' for difftastic; skipping"
        return
        ;;
    esac

    want="$(curl -fsSL https://api.github.com/repos/Wilfred/difftastic/releases/latest 2>/dev/null |
        grep -m1 '"tag_name"' | sed -E 's/.*"v?([0-9.]+)".*/\1/' || true)"
    if [ -z "$want" ]; then
        warn "dev: could not determine latest difftastic version (offline/rate-limited?); skipping difftastic"
        return
    fi

    # The binary is called 'difft', not 'difftastic'.
    if command -v difft >/dev/null 2>&1; then
        current="$(difft --version 2>/dev/null | awk 'NR==1{print $2}')"
        if [ "$current" = "$want" ]; then
            ok "dev: difftastic already installed ($current)"
            return
        fi
        info "dev: updating difftastic ($current -> $want)"
    else
        info "dev: installing difftastic $want"
    fi

    tarball="difft-${dt_arch}-unknown-linux-gnu.tar.gz"
    url="https://github.com/Wilfred/difftastic/releases/download/${want}/${tarball}"
    run "curl -fsSL '$url' -o '/tmp/${tarball}'"
    run "sudo tar -C /usr/local/bin -xzf '/tmp/${tarball}' difft"
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

    # Stable RustDesk cannot do unattended access on Wayland, which is what
    # Ubuntu logs into by default, so x86_64 takes upstream's preview build
    # instead: https://rustdesk.com/blog/unattended-remote-access-wayland/
    # There is no aarch64 preview yet, so arm64 stays on the stable release.
    if [ "$arch" = "amd64" ]; then
        install_rustdesk_wayland
        return
    fi

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

install_rustdesk_wayland() {
    local meta asset deb url built current stamp_dir stamp tmp

    # The preview ships as its own 'rustdesk-unattended-wayland' package that
    # Conflicts/Replaces/Provides 'rustdesk', and it is published only under the
    # rolling 'nightly' tag -- so ask the API for the asset rather than guessing
    # a filename: the version in the name moves, and so does the build behind it.
    meta="$(curl -fsSL https://api.github.com/repos/rustdesk/rustdesk/releases/tags/nightly 2>/dev/null || true)"
    asset="$(printf "%s\n" "$meta" | awk -F'"' '
        /"name": "rustdesk-unattended-wayland-.*-x86_64\.deb"/ { hit = 1; name = $4 }
        hit && /"updated_at":/ { updated = $4 }
        hit && /"browser_download_url":/ { print name, $4, updated; exit }')"
    deb="$(printf "%s" "$asset" | awk '{print $1}')"
    url="$(printf "%s" "$asset" | awk '{print $2}')"
    built="$(printf "%s" "$asset" | awk '{print $3}')"
    if [ -z "$url" ]; then
        warn "dev: no rustdesk Wayland preview asset found (offline/rate-limited?); skipping rustdesk"
        return
    fi

    # Every rebuild of the rolling tag keeps the same package version, so the
    # asset's upload time is the only thing that moves -- stamp it, the way the
    # wezterm nightly stamps its checksum, to avoid re-downloading ~23MB a run.
    stamp_dir="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
    stamp="$stamp_dir/rustdesk-unattended-wayland.stamp"
    current="$(dpkg-query -W -f='${Version}' rustdesk-unattended-wayland 2>/dev/null || true)"
    if [ -n "$current" ] && [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$built" ]; then
        ok "dev: rustdesk Wayland preview already up to date ($current, built $built)"
        return
    fi

    if [ $DRY_RUN -eq 1 ]; then
        echo "• curl -fsSL '$url' -o '/tmp/${deb}'"
        if dpkg -s rustdesk >/dev/null 2>&1; then
            echo "• sudo apt-get remove -y rustdesk"
        fi
        echo "• sudo apt-get install -y '/tmp/${deb}'"
        return
    fi

    if [ -n "$current" ]; then
        info "dev: refreshing the rustdesk Wayland preview ($current, built $built)"
    else
        info "dev: installing the rustdesk Wayland preview ($deb)"
    fi

    tmp="/tmp/${deb}"
    if ! curl -fsSL "$url" -o "$tmp"; then
        warn "dev: rustdesk Wayland preview download failed (offline?); skipping rustdesk"
        return
    fi

    # 'remove', not purge: /root/.config/rustdesk holds the ID and permanent
    # password the service authenticates unattended sessions with.
    if dpkg -s rustdesk >/dev/null 2>&1; then
        info "dev: removing the stable rustdesk (replaced by the Wayland preview)"
        sudo apt-get remove -y rustdesk
    fi
    sudo apt-get install -y "$tmp"
    rm -f "$tmp"

    # The postinst enables and starts rustdesk.service itself, but that raced
    # with the removal above and left the unit disabled; unattended access needs
    # the root service up before anyone has logged in, so make it stick.
    if command -v systemctl >/dev/null 2>&1 && ! sudo systemctl enable --now rustdesk; then
        warn "dev: could not enable rustdesk.service -- unattended access needs it running"
    fi

    mkdir -p "$stamp_dir" && printf "%s\n" "$built" >"$stamp"
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

# ---------- Third-party apt repos ----------
# Declared in packages/linux.txt as:
#   repo <name> url=<URI> suite=<suite> comps=<components> key=<keyurl> [arch=<arch>]
# Writes a deb822 .sources file plus a dearmored keyring, matching the format
# Ubuntu itself now uses. Re-running is a no-op once the files match -- and the
# key URL is part of what has to match, so a rotated key is refetched rather
# than silently kept.
APT_NEEDS_UPDATE=0

install_repo() {
    local line="$1" name url suite comps key arch tok k v
    name="$(printf "%s" "$line" | awk '{print $1}')"
    url=""; suite=""; comps="main"; key=""; arch=""

    for tok in $(printf "%s" "$line" | cut -s -d' ' -f2-); do
        k="${tok%%=*}"; v="${tok#*=}"
        case "$k" in
        url) url="$v" ;;
        suite) suite="$v" ;;
        comps | components) comps="$v" ;;
        key) key="$v" ;;
        arch) arch="$v" ;;
        *) warn "repo $name: unknown field '$k'" ;;
        esac
    done

    if [ -z "$url" ] || [ -z "$suite" ] || [ -z "$key" ]; then
        err "repo $name: url=, suite= and key= are all required; skipping"
        return
    fi

    local keyring="/etc/apt/keyrings/${name}.gpg"
    local srcfile="/etc/apt/sources.list.d/${name}.sources"
    local body
    # The key URL is recorded as a comment, and so is part of the comparison
    # below. Without it a rotated key is never refetched: the .sources file
    # still matches, the old keyring is still non-empty, and every apt-get
    # update fails with NO_PUBKEY until someone deletes the keyring by hand.
    # Spotify publishes each new signing key under its own long key id rather
    # than redirecting one stable URL, so this is not hypothetical. apt ignores
    # '#' lines in deb822 sources.
    body="# key: ${key}
Types: deb
URIs: ${url}
Suites: ${suite}
Components: ${comps}"
    [ -n "$arch" ] && body="${body}
Architectures: ${arch}"
    body="${body}
Signed-By: ${keyring}"

    if [ -f "$srcfile" ] && [ -s "$keyring" ] && [ "$(cat "$srcfile")" = "$body" ]; then
        ok "repo: $name already configured"
        return
    fi

    info "repo: configuring $name"
    if [ $DRY_RUN -eq 1 ]; then
        echo "• curl -fsSL '$key' | gpg --dearmor  (validated, then installed as $keyring)"
        echo "• write $srcfile"
        APT_NEEDS_UPDATE=1
        return
    fi

    sudo install -d -m 0755 /etc/apt/keyrings
    # Fetch into a temp file and validate before touching the installed
    # keyring, so a bad fetch cannot clobber a working one. --dearmor rejects
    # anything that is not OpenPGP data, which covers the usual failure of a
    # dead URL answering 200 with an error page; the keyid check below is for
    # input that parses but carries no public key, and it supplies the log
    # line naming what actually signs the repo.
    # --yes because mktemp has already created the file.
    local tmpkey keyids
    tmpkey="$(mktemp)"
    if ! curl -fsSL "$key" | gpg --dearmor --yes -o "$tmpkey"; then
        rm -f "$tmpkey"
        err "repo $name: could not fetch/dearmor key from $key; skipping"
        return
    fi
    keyids="$(gpg --show-keys --with-colons "$tmpkey" 2>/dev/null | awk -F: '/^pub:/{print $5}' | tr '\n' ' ')"
    if [ -z "$keyids" ]; then
        rm -f "$tmpkey"
        err "repo $name: $key returned no public key; leaving the current keyring alone"
        return
    fi
    sudo install -m 0644 "$tmpkey" "$keyring"
    rm -f "$tmpkey"
    info "repo: $name signed by ${keyids% }"
    printf "%s\n" "$body" | sudo tee "$srcfile" >/dev/null
    APT_NEEDS_UPDATE=1
}

install_ppa() {
    local ppa="$1"
    # add-apt-repository is idempotent and handles the Launchpad key itself.
    if grep -rqs "ppa.launchpadcontent.net/${ppa}/" /etc/apt/sources.list.d/ 2>/dev/null; then
        ok "ppa: $ppa already configured"
        return
    fi
    if ! command -v add-apt-repository >/dev/null 2>&1; then
        info "installing software-properties-common (for add-apt-repository)"
        run "sudo apt-get install -y software-properties-common"
    fi
    info "ppa: adding $ppa"
    run "sudo add-apt-repository -y 'ppa:${ppa}'"
    APT_NEEDS_UPDATE=1
}

# ---------- Apt pin preferences ----------
# Declared in packages/linux.txt as:
#   pin <name> pkg=<glob> priority=<n> [origin=<host>] [release=<expr>]
# Writes /etc/apt/preferences.d/<name>. Needed whenever version order alone
# picks the wrong package: see the firefox pins in packages/linux.txt, where
# Ubuntu's stub carries an epoch that outranks Mozilla's real releases.
install_pin() {
    local line="$1" name pkg prio origin release tok k v target pinfile body
    name="$(printf "%s" "$line" | awk '{print $1}')"
    pkg="*"; prio=""; origin=""; release=""

    # -f so a 'pkg=*' token is not pathname-expanded by the unquoted loop.
    set -f
    for tok in $(printf "%s" "$line" | cut -s -d' ' -f2-); do
        k="${tok%%=*}"; v="${tok#*=}"
        case "$k" in
        pkg | package) pkg="$v" ;;
        priority) prio="$v" ;;
        origin) origin="$v" ;;
        release) release="$v" ;;
        *) warn "pin $name: unknown field '$k'" ;;
        esac
    done
    set +f

    if [ -z "$prio" ] || { [ -z "$origin" ] && [ -z "$release" ]; }; then
        err "pin $name: priority= and one of origin=/release= are required; skipping"
        return
    fi

    if [ -n "$origin" ]; then target="origin ${origin}"; else target="release ${release}"; fi

    pinfile="/etc/apt/preferences.d/${name}"
    body="Package: ${pkg}
Pin: ${target}
Pin-Priority: ${prio}"

    if [ -f "$pinfile" ] && [ "$(cat "$pinfile")" = "$body" ]; then
        ok "pin: $name already configured"
        return
    fi

    info "pin: configuring $name ($pkg -> $prio)"
    if [ $DRY_RUN -eq 1 ]; then
        echo "• write $pinfile"
        return
    fi
    sudo install -d -m 0755 /etc/apt/preferences.d
    printf "%s\n" "$body" | sudo tee "$pinfile" >/dev/null
}

APT_INDEX_FRESH=0
if [ "${#REPO_LINES[@]}" -gt 0 ] || [ "${#PPA_LINES[@]}" -gt 0 ] || [ "${#PIN_LINES[@]}" -gt 0 ]; then
    info "Configuring apt repos..."
    for line in "${REPO_LINES[@]}"; do install_repo "$line"; done
    for line in "${PPA_LINES[@]}"; do install_ppa "$(printf "%s" "$line" | awk '{print $1}')"; done
    # Pins last: they only matter once the sources they refer to exist.
    for line in "${PIN_LINES[@]}"; do install_pin "$line"; done

    # Refresh once here so newly added repos are visible to the installs below.
    if [ $APT_NEEDS_UPDATE -eq 1 ]; then
        info "Refreshing apt index (repos changed)"
        run "sudo apt-get update -y"
        APT_INDEX_FRESH=1
    fi
fi

# ---------- APT installs ----------
if [ "${#APT_PKGS[@]}" -gt 0 ]; then
    info "Preparing apt..."
    # Skip the refresh if the repo step above already did one.
    if [ $APT_INDEX_FRESH -eq 1 ]; then
        ok "apt: index already refreshed"
    elif [ $DRY_RUN -eq 0 ]; then
        sudo apt-get update -y
    else
        echo "• sudo apt-get update -y"
    fi

    for pkg in "${APT_PKGS[@]}"; do
        if apt_installed "$pkg" && ! apt_pin_switch "$pkg"; then
            ok "apt: $pkg already installed"
        elif ! apt_available "$pkg"; then
            warn "apt: $pkg not available on this release; skipping"
            APT_SKIPPED+=("$pkg")
        else
            apt_flags=""
            if apt_installed "$pkg"; then
                # A pin picked a different build. It can sort *lower* than what
                # is installed -- Ubuntu's firefox stub is 1:1snap1-0ubuntu5 and
                # that epoch outranks Mozilla's 154.x -- so permit the apparent
                # downgrade rather than having apt refuse the switch.
                info "apt: switching $pkg to the pinned $(apt_candidate "$pkg")"
                apt_flags="--allow-downgrades "
            else
                info "apt: installing $pkg"
            fi
            # Non-fatal: a single bad package must not strand the dev/font steps.
            if ! run "sudo apt-get install -y ${apt_flags}'$pkg'"; then
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
        rust) install_rust "$(printf "%s" "$line" | cut -s -d' ' -f2-)" ;;
        go) install_go ;;
        msvc-cross) install_msvc_cross ;;
        android-sdk) install_android_sdk ;;
        node) install_node ;;
        neovim) install_neovim ;;
        claude) install_claude ;;
        wezterm) install_wezterm ;;
        lazygit) install_lazygit ;;
        glow) install_glow ;;
        rustdesk) install_rustdesk ;;
        difftastic) install_difftastic ;;
        chrome) install_chrome ;;
        *) warn "Unknown dev tool '$tool' in line: dev $line" ;;
        esac
    done
    warn "Dev toolchains: open a new shell (or 'source ~/.zshrc') to pick up PATH changes."
fi

# ---------- CARGO crates ----------
# After the dev toolchains, not before: 'dev rust' is what puts cargo on disk.
if [ "${#CARGO_LINES[@]}" -gt 0 ]; then
    info "Installing cargo crates..."
    for line in "${CARGO_LINES[@]}"; do
        install_cargo_crate "$line"
    done
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
