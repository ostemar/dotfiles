# 🚀 Dotfiles

My personal dotfiles for setting up development environments on Windows and
Linux (including WSL). These configs help me quickly bootstrap new machines and
keep my setup consistent across systems.

## ✨ What's Included

### 🖥️ Cross-Platform

- **Neovim** - Full LazyVim configuration with custom plugins
- **Bat** - Syntax highlighting for cat with Catppuccin Mocha theme
- **Git** - Configuration and tooling
- Modern CLI tools (ripgrep, fzf, fd, bat, etc.)

### 🪟 Windows-Specific

- **PowerShell** profile with [Oh My Posh](https://ohmyposh.dev/)
- Terminal Icons and colorized output
- Posh-Git integration
- Automated package installation via Chocolatey/Winget

### 🐧 Linux-Specific

- **Zsh** configuration with
  [Powerlevel10k](https://github.com/romkatv/powerlevel10k)
- [Zinit](https://github.com/zdharma-continuum/zinit) plugin manager
- Auto-suggestions, syntax highlighting, and fuzzy completion
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

3. **Create symlinks:**

   ```bash
   ./scripts/setup.sh
   ```

4. **Change your default shell to Zsh** (optional):

   ```bash
   chsh -s $(which zsh)
   ```

5. **Log out and back in** to activate Zsh

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
    └── setup.ps1          # Create symlinks (Windows)
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
apt  package-name           # APT packages
snap package-name --classic # Snap packages (skipped on WSL)
flat app.id                 # Flatpak apps (skipped on WSL)
```

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
| `setup.ps1`           | Creates symlinks for Neovim and PowerShell configs | `-WhatIf` for dry-run mode          |

### Linux

| Script             | Description                                 | Options                               |
| ------------------ | ------------------------------------------- | ------------------------------------- |
| `install_linux.sh` | Installs packages from `packages/linux.txt` | `--dry-run`, `--repo PATH`            |
| `setup.sh`         | Creates symlinks for Neovim and Zsh configs | `--dry-run`, `--force`, `--repo PATH` |

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
