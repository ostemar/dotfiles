# 🚀 Dotfiles

My personal dotfiles for setting up development environments on Windows and
Linux (including WSL). These configs help me quickly bootstrap new machines and
keep my setup consistent across systems.

## ✨ What's Included

### 🖥️ Cross-Platform

- **Neovim** - Full LazyVim configuration with custom plugins
- **WezTerm** - Terminal config (Catppuccin Mocha, JetBrainsMono Nerd Font,
  vim-style pane keybinds; platform-guarded for Windows/Linux)
- **Bat** - Syntax highlighting for cat with Catppuccin Mocha theme
- **Claude Code** - Global `CLAUDE.md`, per-platform rules, personal skills
  and the Catppuccin Mocha theme, linked into `~/.claude`
- **Git** - Configuration and tooling
- Modern CLI tools (ripgrep, fzf, fd, bat, etc.)

### 🪟 Windows-Specific

- **PowerShell** profile with [Oh My Posh](https://ohmyposh.dev/)
- Terminal Icons and colorized output
- Posh-Git integration
- Automated package installation via Chocolatey/Winget
- **GlazeWM** tiling window manager with the Windows key as the modifier, plus
  a **Zebar** status bar carrying a working system tray. Windows only; the
  Linux scripts never touch either. See [GlazeWM and Zebar](#-glazewm-and-zebar).

### 🐧 Linux-Specific

- **Zsh** configuration with
  [Powerlevel10k](https://github.com/romkatv/powerlevel10k)
- [Zinit](https://github.com/zdharma-continuum/zinit) plugin manager
- Auto-suggestions, syntax highlighting, and fuzzy completion
- **WezTerm** installed from the upstream nightly `.deb` (not apt, not
  snap/flatpak) plus the JetBrainsMono Nerd Font it needs
- Support for both native Ubuntu and WSL

## 🎯 Quick Start

### Windows

1. **Clone the repository:**

   ```powershell
   git clone https://github.com/ostemar/dotfiles.git C:\git\dotfiles
   cd C:\git\dotfiles
   ```

2. **Install packages and create symlinks:**

   ```powershell
   # Install everything and set up symlinks
   .\scripts\install_windows.ps1 -RunSetup

   # Or do it in steps:
   .\scripts\install_windows.ps1  # Just install packages
   .\scripts\setup.ps1             # Just create symlinks
   ```

3. **Restart your terminal** to load the new PowerShell profile

### Linux / WSL

1. **Clone the repository:**

   ```bash
   git clone https://github.com/ostemar/dotfiles.git ~/dotfiles
   cd ~/dotfiles
   ```

2. **Install packages:**

   ```bash
   ./scripts/install_linux.sh
   ```

3. **Create symlinks and set default shell:**

   ```bash
   ./scripts/setup.sh
   ```

   This will link all config files and automatically set zsh as your default
   shell.

4. **Log out and back in** to activate Zsh

## 📁 Repository Structure

```
dotfiles/
├── bat/                    # Bat (cat with syntax highlighting)
│   ├── config             # Bat configuration with Catppuccin Mocha theme
│   └── themes/
│       └── Catppuccin Mocha.tmTheme
├── nvim/                    # Neovim configuration (LazyVim)
│   ├── lua/
│   │   ├── config/         # Core configuration
│   │   └── plugins/        # Custom plugins
│   └── init.lua
├── powershell/             # PowerShell configuration
│   ├── Microsoft.PowerShell_profile.ps1
│   └── .oh-my-posh.ostemar.json
├── wezterm/                # WezTerm terminal config
│   └── wezterm.lua
├── glazewm/                # GlazeWM tiling WM config (Windows only)
│   └── config.yaml
├── zebar/                  # Zebar status bar (Windows only)
│   ├── settings.json      # Which pack/widget starts (copied, not linked)
│   └── martin-bar/        # The widget pack itself
│       ├── zpack.json
│       ├── topbar.html
│       ├── styles.css
│       └── vendor/        # Vendored deps, so the bar needs no network
├── zsh/                    # Zsh configuration
│   └── .zshrc
├── packages/               # Package lists
│   ├── linux.txt          # APT, Snap, and Flatpak packages
│   ├── windows.txt        # Chocolatey/Winget packages
│   └── powershell_modules.txt
└── scripts/               # Installation and setup scripts
    ├── install_linux.sh   # Install Linux packages
    ├── install_windows.ps1
    ├── setup.sh           # Create symlinks (Linux)
    ├── setup.ps1          # Create symlinks (Windows)
    └── setup_glazewm_windows.ps1  # GlazeWM autostart + registry policies
```

## 🔧 Customization

### Adding Packages

#### Windows

Edit `packages/windows.txt` and add package names (one per line):

```
neovim
ripgrep
your-package-here
```

Then run:

```powershell
.\scripts\install_windows.ps1
```

#### Linux

Edit `packages/linux.txt` using the format:

```
repo name url=... suite=... comps=... key=...   # Third-party apt source
ppa  owner/name             # Launchpad PPA
apt  package-name           # APT packages
snap package-name --classic # Snap packages (skipped on WSL)
flat app.id                 # Flatpak apps (skipped on WSL)
dev  toolchain [args...]    # Upstream installers (rust, go, node, neovim,
                            #   claude, wezterm, lazygit, glow) -- used
                            #   where apt lags or has no package at all.
                            #   'dev rust' takes extra rustup targets, e.g.
                            #   'dev rust wasm32-unknown-unknown'
cargo crate [--flags]       # cargo install --locked <crate> (needs 'dev rust')
font NerdFontName           # Nerd Fonts into ~/.local/share/fonts
                            #   (skipped on WSL)
```

`repo` and `ppa` entries are applied before any `apt` install, so an `apt` line
may depend on a source declared above it. `repo` writes a deb822 `.sources` file
plus a dearmored keyring under `/etc/apt/keyrings`.

`dev` and `font` entries fetch the current upstream release and are idempotent:
re-running `install_linux.sh` is also how you update them.

`cargo` entries run after the `dev` toolchains, since `dev rust` is what puts
cargo on disk. They are **never** reinstalled once present: they compile from
source and take minutes, and none of them self-updates, so an installer re-run
is the wrong place to discover a new release. Use `cargo install --force
<crate>` for that.

Then run:

```bash
./scripts/install_linux.sh
```

### PowerShell Modules

Add modules to `packages/powershell_modules.txt` and run the install script.

## 🛠️ Scripts Reference

### Windows

| Script                | Description                                        | Options                             |
| --------------------- | -------------------------------------------------- | ----------------------------------- |
| `install_windows.ps1` | Installs packages and optionally runs setup        | `-RunSetup` to also create symlinks |
| `setup.ps1`           | Creates symlinks for Neovim, WezTerm, PowerShell, and tool configs | `-WhatIf` for dry-run mode          |
| `setup_glazewm_windows.ps1` | GlazeWM/Zebar machine state: autostart, registry policies, elevation flag | `-SkipScheduledTask`, `-WhatIf` |

### Linux

| Script             | Description                                                  | Options                               |
| ------------------ | ------------------------------------------------------------ | ------------------------------------- |
| `install_linux.sh` | Installs packages from `packages/linux.txt`                  | `--dry-run`, `--repo PATH`            |
| `setup.sh`         | Creates symlinks for configs; sets zsh as default shell      | `--dry-run`, `--force`, `--repo PATH` |

All scripts are **idempotent** and safe to re-run. They will:

- ✅ Skip already-installed packages
- ✅ Back up existing configs (unless `--force` is used)
- ✅ Detect WSL and skip GUI apps automatically

## 💡 Features

### PowerShell Profile Highlights

- 🎨 Beautiful Oh My Posh theme
- 📁 Colorized directory listings
- 🔀 Git integration with posh-git
- 🎯 Terminal Icons
- 🏠 `~` alias to jump to home directory
- 🔤 Unicode helper function

### Zsh Configuration Highlights

- ⚡ Fast startup with Zinit
- 🎨 Powerlevel10k theme
- 🔍 Fuzzy finding with fzf
- 📝 Syntax highlighting
- 💡 Auto-suggestions
- 📂 Smart completions with fzf-tab
- 🚀 Zoxide for smart directory jumping

### Neovim Configuration

Based on [LazyVim](https://www.lazyvim.org/) with additional customizations:

- 📝 Live markdown preview
- 🎨 Tokyo Night theme
- 🍿 Snacks.nvim for UI enhancements
- 🔍 Full LSP support

### Bat Configuration

- 🎨 Catppuccin Mocha theme for beautiful syntax highlighting
- 📊 Line numbers and Git modifications display
- 🔍 Custom syntax mappings for common file types
- 📄 Smart paging with mouse support

## 🪟 GlazeWM and Zebar

Windows only. `scripts/setup.sh` never references either directory, so nothing
here reaches a Linux or WSL machine.

Setup is two steps, because config files and machine state are separate
problems:

```powershell
# 1. Link the configs (needs Developer Mode or an elevated shell)
.\scripts\setup.ps1

# 2. Machine state: autostart, registry policies, elevation flag
.\scripts\setup_glazewm_windows.ps1        # run elevated
```

### Why the second script exists

`config.yaml` cannot express any of the following, and all of it is
load-bearing.

**`RUNASADMIN` on `glazewm.exe`.** The keyboard hook cannot see input while an
elevated window has focus. Without the flag a modifier key-up gets missed and
bare keys start firing WM commands.

**`NoWinKeys=1`.** With Win as the modifier, a `win+` combo leaves the Start
menu open afterwards. Open bug,
[glzr-io/glazewm#1215](https://github.com/glzr-io/glazewm/issues/1215).

**A scheduled task rather than the tray toggle.** GlazeWM's own "Run on system
startup" writes a `CurrentVersion\Run` entry, and Run entries launch with the
filtered, non-elevated token. Combined with the flag above that means a UAC
prompt every logon, or silence. A logon task with `RunLevel Highest` is the
only way to start it elevated and quietly. Leave the tray toggle **off**, or
you get two instances.

**Zebar started separately.** It is deliberately not in GlazeWM's
`startup_commands`. A child of the elevated GlazeWM inherits elevation, and an
elevated Zebar breaks its own system tray: the tray works by receiving
`WM_COPYDATA` broadcasts from other apps, and UIPI blocks messages sent from a
lower integrity level to a higher one. A Startup-folder shortcut keeps Zebar at
normal integrity.

### The Win+L collision

Windows reserves Win+L for lock at a level below any keyboard hook, so a plain
`win+l` binding can never reach GlazeWM. That is awkward for a vim layout,
where `l` is focus-right.

The fix is that Windows hotkeys match their modifier set **exactly**. Win+Alt+L
is a different chord, so winlogon's Win+L handler never sees it. The four focus
bindings therefore use `win+alt+hjkl`, and everything else stays on plain
`win+` or `win+shift+`. Arrow aliases stay on plain `win+` since they were
never affected.

The obvious alternative, `DisableLockWorkstation=1`, frees plain `win+l` but
disables the `LockWorkStation` API outright: the machine then cannot be locked
at all, not by key, not by API, not from the Ctrl+Alt+Del screen. One keystroke
is not worth that on a laptop, so this repo does not offer it. If a machine
still carries that policy from an earlier setup,
`setup_glazewm_windows.ps1` warns and tells you how to clear it.

### The status bar

`zebar/martin-bar/` is a local pack rather than the stock `glzr-io.starter`.
The starter lives under Program Files, is replaced on every Zebar update, and
describes itself as being for testing and development. It also pulled React,
ReactDOM, a Babel JSX transpiler and a webfont from public CDNs on every start,
three of them unpinned and none of the modules integrity-checked. This pack is
plain DOM with the Zebar client API vendored, so it starts with no network.

Icons come from JetBrainsMono Nerd Font, listed in `packages/windows.txt`.
Without it the bar renders tofu.

The tray splits into pinned icons and an overflow behind a caret, mirroring
Windows' own show/hide split. It cannot read that Windows setting: the provider
exposes only an id, a tooltip and a bitmap, never the `IsPromoted` flag. Pin by
tooltip substring via `PINNED_TOOLTIPS`, or, for apps that register no tooltip
at all (Dropbox, Slack and 1Password among them), by GUID via `PINNED_IDS`.
Find a GUID under `HKCU\Control Panel\NotifyIconSettings`, where each subkey
carries an `ExecutablePath` and an `IconGuid`.

## 🤝 Using These Dotfiles

Feel free to fork this repository and customize it for your own use! Here's how:

1. **Fork the repo** to your GitHub account
2. **Clone your fork** instead of mine
3. **Customize** the configs to match your preferences
4. **Update package lists** in `packages/` with your favorite tools
5. **Modify** PowerShell/Zsh configs to add your aliases and functions

## 📝 Notes

- **Windows symlinks** require either Developer Mode enabled or running
  PowerShell as Administrator
- **WSL detection** automatically skips snap and flatpak packages on WSL
- **Backup files** are created with timestamps (`.bak.YYYYMMDD-HHMMSS`) unless
  `--force` is used
- All scripts support **dry-run mode** so you can preview changes before
  applying them

## 🔧 Troubleshooting

### Zsh Startup Errors

If you see errors when starting zsh, here are common issues and fixes:

#### "no such file or directory: .../zsh-syntax-highlighting.zsh^M"

**Cause:** Zinit plugins were cloned with Windows line endings (CRLF) instead of Unix (LF).

**Fix:**
```bash
# Remove corrupted plugins
rm -rf ~/.local/share/zinit/plugins/

# Restart zsh - plugins will auto-reinstall with correct line endings
zsh
```

**Prevention:** The `.gitattributes` file in this repo ensures correct line endings across platforms.

#### "no such file or directory: /home/linuxbrew/.linuxbrew/bin/brew"

**Cause:** Homebrew is not installed (it's optional).

**Fix:** Either install Homebrew or ignore - the `.zshrc` will skip it automatically after the fix is applied.

To install Homebrew on Linux:
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

#### "unknown option: --zsh" (fzf error)

**Cause:** Ubuntu 24.04 LTS ships with fzf 0.44.1, but the `--zsh` flag requires fzf 0.48+.

**Fix:** The updated `.zshrc` uses the Ubuntu 24.04 compatible initialization method.

**Future upgrade:** When you upgrade to Ubuntu 25.04+ or install fzf 0.48+, you can simplify the fzf initialization to just: `eval "$(fzf --zsh)"`

#### "no such file or directory: ~/.local/bin/env"

**Cause:** Optional env file doesn't exist (from previous bash setup).

**Fix:** The updated `.zshrc` makes this conditional. The functionality (adding `~/.local/bin` to PATH) is now built into `.zshrc`.

### Cross-Platform Line Endings

This repo uses `.gitattributes` to manage line endings:
- **Shell scripts** (`.sh`, `.zsh`, `.bash`): Always use LF (Unix)
- **PowerShell scripts** (`.ps1`): Always use CRLF (Windows)
- Git handles conversions automatically

**If you see `^M` characters in files:**
1. Check that `.gitattributes` exists in the repo root
2. Run: `git rm --cached -r . && git reset --hard`
3. This will re-checkout all files with correct line endings

### Managing Git Config

This repo will soon include git configuration templates for:
- **Platform differences:** Windows vs Linux paths and tools
- **Context switching:** Personal vs work email addresses

For now, configure git manually:
```bash
# Personal machine
git config --global user.email "your-personal@email.com"

# Work machine
git config --global user.email "your-work@email.com"
```

### WSL-Specific Notes

- **Snap/Flatpak packages:** Automatically skipped by `install_linux.sh`
- **Line endings:** WSL respects `.gitattributes` - no special handling needed
- **Performance:** If zsh is slow to start in WSL, check Windows Defender exclusions

## 📜 License

MIT License - see [LICENSE](LICENSE) file for details.

---

Made with ❤️ for automating the boring stuff
