# Agent Guidelines for Dotfiles Repository

## Repository Type
Personal dotfiles for cross-platform development environment setup (Windows/Linux/WSL).

## File Structure
- `scripts/` - Installation and setup scripts (bash/PowerShell)
- `nvim/` - Neovim/LazyVim configuration
- `zsh/` - Zsh shell configuration  
- `powershell/` - PowerShell profile and Oh My Posh theme
- `bat/`, `delta/`, `lazygit/` - Tool configurations
- `packages/` - Package lists for apt, snap, flatpak, chocolatey, winget
- `claude/` - Claude Code config linked into `~/.claude` (see `claude/README.md`)
- `bin/` - Small commands the setup scripts put on PATH. Cross-platform ones
  come in pairs: an extension-less Bash script for Linux and Git Bash, and a
  `.ps1` twin for PowerShell. Keep a pair in sync; their output should match

## Line Endings (CRITICAL)
- Shell scripts (`.sh`, `.bash`, `.zsh`, `.zshrc`, everything in `bin/` without
  an extension): Always LF (Unix). A CRLF in a shebang line makes Linux refuse
  to run the file at all
- PowerShell scripts (`.ps1`, `.psm1`, `.bat`, `.cmd`): Always CRLF (Windows)
- Config files (`.lua`, `.json`, `.yaml`, `.md`, `.txt`): LF
- See `.gitattributes` for complete rules - NEVER modify line endings manually

## Code Style
- **Bash**: Use `set -euo pipefail`, prefer functions over globals, emoji prefixes for output (`info()`, `ok()`, `warn()`, `err()`)
- **PowerShell**: PascalCase functions, verbose parameter names, prefer cmdlets over aliases in scripts
- **Formatting**: Markdown prose wrap at 80 chars (see `.prettierrc.yaml`)
- **Idempotency**: All scripts must be safe to re-run (check before install, backup before overwrite)

## Key Patterns
- Scripts support `--dry-run` mode for safety
- WSL detection: `grep -qi microsoft /proc/version` (bash) or check in PowerShell
- Backup files use timestamp: `.bak.YYYYMMDD-HHMMSS`
- Skip already-installed packages automatically
