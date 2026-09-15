<#
.SYNOPSIS
  Create Windows symlinks for your dotfiles:
  - %LOCALAPPDATA%\nvim  →  <repo>\nvim
  - %APPDATA%\bat  →  <repo>\bat
  - %USERPROFILE%\.wezterm.lua  →  <repo>\wezterm\wezterm.lua
  - For each file in <repo>\powershell\ →  $HOME\Documents\PowerShell\
    * Special-case: Microsoft.PowerShell_profile.ps1 → $PROFILE
  - For each entry in <repo>\claude\ →  $HOME\.claude\ (see claude\README.md)
  - <repo>\bin  added to the user PATH (commands, not config: no symlink needed)

.DESCRIPTION
  - Safe to re-run. Cleans existing targets when necessary.
  - Links directories for nvim and bat; files for PowerShell.
  - If symlink creation fails (no admin / Developer Mode), shows a helpful hint.
  - Removes $HOME\.claude links whose repo entry was renamed or deleted.
  - Runs 'bat cache --build' after linking bat config (if bat is installed).

.PARAMETER RepoRoot
  Optional path to the repo root. Defaults to the parent of this script folder.

.PARAMETER WhatIf
  Dry-run mode (built-in switch). Shows what would happen without making changes.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [string]$RepoRoot
)

# ---------- Resolve paths ----------------------------------------------------
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $RepoRoot -or $RepoRoot.Trim() -eq "") {
  $RepoRoot = Split-Path -Parent $SCRIPT_DIR
}

# Key repo paths
$NvimSource      = Join-Path $RepoRoot "nvim"
$BatSource       = Join-Path $RepoRoot "bat"
$DeltaSource     = Join-Path $RepoRoot "delta"
$LazygitSource   = Join-Path $RepoRoot "lazygit"
$WeztermSource   = Join-Path $RepoRoot "wezterm\wezterm.lua"
$PwshRepoDir     = Join-Path $RepoRoot "powershell"
$ClaudeSource    = Join-Path $RepoRoot "claude"
$BinSource       = Join-Path $RepoRoot "bin"
$GlazewmSource   = Join-Path $RepoRoot "glazewm\config.yaml"
$ZebarPackSource = Join-Path $RepoRoot "zebar\martin-bar"
$ZebarSettings   = Join-Path $RepoRoot "zebar\settings.json"

# Key user paths
$NvimTarget      = Join-Path $env:LOCALAPPDATA "nvim"
$BatTarget       = Join-Path $env:APPDATA "bat"
$ConfigDir       = Join-Path $HOME ".config"
$DeltaTarget     = Join-Path $ConfigDir "delta"
$LazygitTarget   = Join-Path $env:LOCALAPPDATA "lazygit"
$WeztermTarget   = Join-Path $HOME ".wezterm.lua"
$UserPwshDir     = Split-Path -Parent $PROFILE  # typically: $HOME\Documents\PowerShell
$ProfileTarget   = $PROFILE                     # exact host-specific profile path
$ClaudeTarget    = Join-Path $HOME ".claude"
$GlzrDir         = Join-Path $HOME ".glzr"
$GlazewmTarget   = Join-Path $GlzrDir "glazewm\config.yaml"
$ZebarDir        = Join-Path $GlzrDir "zebar"
$ZebarPackTarget = Join-Path $ZebarDir "martin-bar"

Write-Host "🔗 Dotfiles setup" -ForegroundColor Cyan
Write-Host "  Repo root:  $RepoRoot"
Write-Host "  Neovim:     $NvimSource  →  $NvimTarget"
Write-Host "  Bat:        $BatSource  →  $BatTarget"
Write-Host "  Delta:      $DeltaSource  →  $DeltaTarget"
Write-Host "  Lazygit:    $LazygitSource  →  $LazygitTarget"
Write-Host "  WezTerm:    $WeztermSource  →  $WeztermTarget"
Write-Host "  PS folder:  $PwshRepoDir  →  $UserPwshDir (files only)"
Write-Host "  Claude:     $ClaudeSource  →  $ClaudeTarget (per entry)"
Write-Host "  Commands:   $BinSource  (added to the user PATH)"
Write-Host "  GlazeWM:    $GlazewmSource  →  $GlazewmTarget"
Write-Host "  Zebar pack: $ZebarPackSource  →  $ZebarPackTarget"

# ---------- Helpers ----------------------------------------------------------
function Test-DeveloperModeEnabled {
  try {
    $reg = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" -ErrorAction Stop
    return ($reg.AllowDevelopmentWithoutDevLicense -eq 1)
  } catch {
    return $false
  }
}

function Remove-PathIfExists {
  param([Parameter(Mandatory)][string]$Path)
  if (Test-Path -LiteralPath $Path) {
    $item = Get-Item -LiteralPath $Path -Force
    $desc = if ($item.PSIsContainer) { "directory" } elseif ($item.LinkType) { "symlink ($($item.LinkType))" } else { "file" }
    if ($PSCmdlet.ShouldProcess($Path, "Remove existing $desc")) {
      try {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
      } catch {
        throw "Failed to remove existing path '$Path': $($_.Exception.Message)"
      }
    }
  }
}

function Ensure-ParentDir {
  param([Parameter(Mandatory)][string]$Path)
  $dir = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $dir)) {
    if ($PSCmdlet.ShouldProcess($dir, "Create directory")) {
      New-Item -ItemType Directory -Path $dir | Out-Null
    }
  }
}

function New-SafeSymlink {
  param(
    [Parameter(Mandatory)][string]$LinkPath,
    [Parameter(Mandatory)][string]$TargetPath
  )
  if (-not (Test-Path -LiteralPath $TargetPath)) {
    throw "Target does not exist: $TargetPath"
  }

  Ensure-ParentDir -Path $LinkPath
  Remove-PathIfExists -Path $LinkPath

  if ($PSCmdlet.ShouldProcess("$LinkPath", "Create symbolic link → $TargetPath")) {
    try {
      New-Item -ItemType SymbolicLink -Path $LinkPath -Target $TargetPath -ErrorAction Stop | Out-Null
    } catch {
      $devMode = Test-DeveloperModeEnabled
      $hint = if ($devMode) {
        "Developer Mode appears enabled, but creating a symlink still failed. Try running an elevated PowerShell."
      } else {
        "Enable Developer Mode (Settings → System → For developers) or run PowerShell as Administrator."
      }
      throw "Failed to create symlink '$LinkPath' → '$TargetPath': $($_.Exception.Message)`n$hint"
    }
  }

  # Verify the postcondition instead of trusting that no exception means success.
  # A declined ShouldProcess skips the block above and returns quietly, so the
  # caller would print its success message over a link that was never made. That
  # silently left an old junction in place twice before this check existed.
  if (-not $WhatIfPreference) {
    $result = Get-Item -LiteralPath $LinkPath -Force -ErrorAction SilentlyContinue
    if (-not $result) {
      throw "'$LinkPath' was not created. The operation was skipped, not performed."
    }
    if ($result.LinkType -ne "SymbolicLink") {
      $kind = if ($result.LinkType) { $result.LinkType } else { "a regular file or directory" }
      throw "'$LinkPath' is $kind, not a SymbolicLink. Remove it and re-run."
    }
    $actualTarget = @($result.Target)[0]
    if ($actualTarget -ne $TargetPath) {
      throw "'$LinkPath' points at '$actualTarget', not '$TargetPath'."
    }
  }
}

function Test-SymlinkCapability {
  <#
    Creating a symlink on Windows needs Developer Mode or an elevated shell.
    New-SafeSymlink removes the existing target before it creates the new link,
    so finding this out mid-run leaves a config unlinked and the script aborted.
    Probe once, up front, before anything is removed.

    -WhatIf:$false on each call so the probe really runs during a dry-run too;
    otherwise $WhatIfPreference suppresses it and the probe always says yes.
  #>
  $probeDir = Join-Path ([System.IO.Path]::GetTempPath()) ("dotfiles-symlink-probe-" + [guid]::NewGuid().ToString("N"))
  try {
    New-Item -ItemType Directory -Path $probeDir -WhatIf:$false -ErrorAction Stop | Out-Null
    $probeTarget = Join-Path $probeDir "target.txt"
    Set-Content -LiteralPath $probeTarget -Value "probe" -WhatIf:$false -ErrorAction Stop
    New-Item -ItemType SymbolicLink -Path (Join-Path $probeDir "link.txt") -Target $probeTarget -WhatIf:$false -ErrorAction Stop | Out-Null
    return $true
  } catch {
    return $false
  } finally {
    Remove-Item -LiteralPath $probeDir -Recurse -Force -WhatIf:$false -ErrorAction SilentlyContinue
  }
}

function Install-ClaudeEntries {
  <#
    Symlink each child of a repo claude\<dir> into $HOME\.claude\<dir>, one entry
    at a time. Linking the whole directory would put Claude Code's own writes
    (for example the reserved skills\synced folder) inside the repo.

    Files named <name>.linux.<ext> are for the other platform and are skipped.
  #>
  param(
    [Parameter(Mandatory)][string]$SourceDir,
    [Parameter(Mandatory)][string]$TargetDir
  )

  if (-not (Test-Path -LiteralPath $SourceDir)) { return }

  if (-not (Test-Path -LiteralPath $TargetDir)) {
    if ($PSCmdlet.ShouldProcess($TargetDir, "Create directory")) {
      New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
    }
  }

  foreach ($entry in Get-ChildItem -LiteralPath $SourceDir -Force) {
    if ($entry.Name -like "*.linux.*") {
      Write-Host "⏭️  Skipped $($entry.Name) (Linux only)" -ForegroundColor DarkGray
      continue
    }
    try {
      New-SafeSymlink -LinkPath (Join-Path $TargetDir $entry.Name) -TargetPath $entry.FullName
      Write-Host "✅ Linked $($entry.Name) → $TargetDir" -ForegroundColor Green
    } catch {
      Write-Warning "⚠️ Failed to link $($entry.Name): $($_.Exception.Message)"
    }
  }
}

function Remove-StaleClaudeLinks {
  <#
    Remove links in $HOME\.claude\<dir> that point into the repo claude\<dir> at
    an entry that no longer exists. Renaming, moving, or deleting a repo entry
    leaves one behind. Links pointing anywhere else were not made by this script
    and are left alone.
  #>
  param(
    [Parameter(Mandatory)][string]$SourceDir,
    [Parameter(Mandatory)][string]$TargetDir
  )

  if (-not (Test-Path -LiteralPath $TargetDir)) { return }

  $sourcePrefix = $SourceDir.TrimEnd("\") + "\"
  foreach ($entry in Get-ChildItem -LiteralPath $TargetDir -Force) {
    if (-not $entry.LinkType) { continue }
    $target = @($entry.Target)[0]
    if (-not $target -or -not $target.StartsWith($sourcePrefix, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
    if (Test-Path -LiteralPath $target) { continue }

    if ($PSCmdlet.ShouldProcess($entry.FullName, "Remove stale link → $target")) {
      try {
        Remove-Item -LiteralPath $entry.FullName -Force -ErrorAction Stop
        Write-Host "🧹 Removed stale link $($entry.Name) → $target" -ForegroundColor Yellow
      } catch {
        Write-Warning "⚠️ Failed to remove stale link $($entry.Name): $($_.Exception.Message)"
      }
    }
  }
}

function Add-UserPathEntry {
  <#
    Put a directory on the user PATH if it is not already there.

    This writes the persistent, registry-backed user PATH rather than $env:Path,
    which would last only as long as this process. Git Bash inherits the Windows
    PATH, so the one entry serves PowerShell and Git Bash both.
  #>
  param([Parameter(Mandatory)][string]$Directory)

  $entries = @([Environment]::GetEnvironmentVariable("Path", "User") -split ";" | Where-Object { $_ })
  if ($entries -contains $Directory) {
    Write-Host "✅ Already on the user PATH: $Directory" -ForegroundColor Green
    return
  }

  if ($PSCmdlet.ShouldProcess($Directory, "Add to the user PATH")) {
    $updated = (@($Directory) + $entries) -join ";"
    [Environment]::SetEnvironmentVariable("Path", $updated, "User")
    $env:Path = "$Directory;$env:Path"
    Write-Host "✅ Added to the user PATH: $Directory" -ForegroundColor Green
    Write-Host "ℹ️  Open a new terminal for other shells to see it." -ForegroundColor Yellow
  }
}

# ---------- Preflight --------------------------------------------------------
if (-not (Test-SymlinkCapability)) {
  $hint = if (Test-DeveloperModeEnabled) {
    "Developer Mode appears enabled, but creating a symlink still failed. Try running an elevated PowerShell."
  } else {
    "Enable Developer Mode (Settings → System → For developers) or run PowerShell as Administrator."
  }
  throw "Cannot create symbolic links here, so nothing was changed.`n$hint"
}

# ---------- Validate sources -------------------------------------------------
if (-not (Test-Path -LiteralPath $NvimSource)) {
  throw "Neovim source not found: $NvimSource"
}
if (-not (Test-Path -LiteralPath $PwshRepoDir)) {
  throw "PowerShell repo folder not found: $PwshRepoDir"
}
if (-not (Test-Path -LiteralPath $BatSource)) {
  Write-Warning "⚠️ Bat source not found: $BatSource (skipping bat setup)"
}
if (-not (Test-Path -LiteralPath $DeltaSource)) {
  Write-Warning "⚠️ Delta source not found: $DeltaSource (skipping delta setup)"
}
if (-not (Test-Path -LiteralPath $LazygitSource)) {
  Write-Warning "⚠️ Lazygit source not found: $LazygitSource (skipping lazygit setup)"
}
if (-not (Test-Path -LiteralPath $WeztermSource)) {
  Write-Warning "⚠️ WezTerm source not found: $WeztermSource (skipping wezterm setup)"
}

# ---------- Link Neovim ------------------------------------------------------
try {
  New-SafeSymlink -LinkPath $NvimTarget -TargetPath $NvimSource
  Write-Host "✅ Linked Neovim config" -ForegroundColor Green
} catch {
  Write-Warning "⚠️ Neovim link failed: $($_.Exception.Message)"
  throw
}

# ---------- Link Bat ---------------------------------------------------------
if (Test-Path -LiteralPath $BatSource) {
  try {
    New-SafeSymlink -LinkPath $BatTarget -TargetPath $BatSource
    Write-Host "✅ Linked Bat config" -ForegroundColor Green
    
    # Rebuild bat cache to register the new theme
    if (Get-Command bat -ErrorAction SilentlyContinue) {
      if ($PSCmdlet.ShouldProcess("bat cache", "Rebuild cache")) {
        Write-Host "🔄 Rebuilding bat cache..." -ForegroundColor Cyan
        bat cache --build | Out-Null
        Write-Host "✅ Bat cache rebuilt" -ForegroundColor Green
      }
    } else {
      Write-Host "ℹ️  bat not found in PATH. Install bat and run 'bat cache --build' to use the theme." -ForegroundColor Yellow
    }
  } catch {
    Write-Warning "⚠️ Bat link failed: $($_.Exception.Message)"
  }
}

# ---------- Link Delta -------------------------------------------------------
if (Test-Path -LiteralPath $DeltaSource) {
  try {
    New-SafeSymlink -LinkPath $DeltaTarget -TargetPath $DeltaSource
    Write-Host "✅ Linked Delta config" -ForegroundColor Green
  } catch {
    Write-Warning "⚠️ Delta link failed: $($_.Exception.Message)"
  }
}

# ---------- Link Lazygit -----------------------------------------------------
if (Test-Path -LiteralPath $LazygitSource) {
  try {
    New-SafeSymlink -LinkPath $LazygitTarget -TargetPath $LazygitSource
    Write-Host "✅ Linked Lazygit config" -ForegroundColor Green
  } catch {
    Write-Warning "⚠️ Lazygit link failed: $($_.Exception.Message)"
  }
}

# ---------- Link WezTerm -----------------------------------------------------
if (Test-Path -LiteralPath $WeztermSource) {
  try {
    New-SafeSymlink -LinkPath $WeztermTarget -TargetPath $WeztermSource
    Write-Host "✅ Linked WezTerm config" -ForegroundColor Green
  } catch {
    Write-Warning "⚠️ WezTerm link failed: $($_.Exception.Message)"
  }
}

# ---------- Link PowerShell files (files only) ------------------------------
# We will:
#  - Map 'Microsoft.PowerShell_profile.ps1' -> $PROFILE
#  - Map every other *file* in repo\powershell to $UserPwshDir\<same-name>
#  - Skip directories; do not recurse

# Ensure user PowerShell dir exists for non-profile files
if (-not (Test-Path -LiteralPath $UserPwshDir)) {
  if ($PSCmdlet.ShouldProcess($UserPwshDir, "Create PowerShell user directory")) {
    New-Item -ItemType Directory -Path $UserPwshDir | Out-Null
  }
}

# Get only files (hidden included), top level only
$pwshFiles = Get-ChildItem -LiteralPath $PwshRepoDir -File -Force -ErrorAction Stop

foreach ($file in $pwshFiles) {
  $sourcePath = $file.FullName
  $destPath = if ($file.Name -ieq "Microsoft.PowerShell_profile.ps1") {
    $ProfileTarget
  } else {
    Join-Path $UserPwshDir $file.Name
  }

  try {
    New-SafeSymlink -LinkPath $destPath -TargetPath $sourcePath
    Write-Host "✅ Linked $($file.Name) → $destPath" -ForegroundColor Green
  } catch {
    Write-Warning "⚠️ Failed to link $($file.Name): $($_.Exception.Message)"
    throw
  }
}

# ---------- Link Claude Code config -----------------------------------------
# Claude Code reads ~/.claude/{CLAUDE.md,rules,skills,agents,themes,...} but also
# writes runtime state there (sessions, projects, .credentials.json, plugins), so
# link individual entries rather than the directory itself.
if (Test-Path -LiteralPath $ClaudeSource) {
  Write-Host "🔗 Linking Claude Code config → $ClaudeTarget" -ForegroundColor Cyan

  if (-not (Test-Path -LiteralPath $ClaudeTarget)) {
    if ($PSCmdlet.ShouldProcess($ClaudeTarget, "Create directory")) {
      New-Item -ItemType Directory -Path $ClaudeTarget -Force | Out-Null
    }
  }

  $ClaudeMdSource = Join-Path $ClaudeSource "CLAUDE.md"
  if (Test-Path -LiteralPath $ClaudeMdSource) {
    try {
      New-SafeSymlink -LinkPath (Join-Path $ClaudeTarget "CLAUDE.md") -TargetPath $ClaudeMdSource
      Write-Host "✅ Linked CLAUDE.md → $ClaudeTarget" -ForegroundColor Green
    } catch {
      Write-Warning "⚠️ CLAUDE.md link failed: $($_.Exception.Message)"
    }
  }

  # Referenced by "statusLine" in settings.json as $HOME/.claude/statusline.js.
  $StatusLineSource = Join-Path $ClaudeSource "statusline.js"
  if (Test-Path -LiteralPath $StatusLineSource) {
    try {
      New-SafeSymlink -LinkPath (Join-Path $ClaudeTarget "statusline.js") -TargetPath $StatusLineSource
      Write-Host "✅ Linked statusline.js → $ClaudeTarget" -ForegroundColor Green
    } catch {
      Write-Warning "⚠️ statusline.js link failed: $($_.Exception.Message)"
    }
  }

  foreach ($name in @("rules", "skills", "agents", "output-styles", "themes", "workflows")) {
    Remove-StaleClaudeLinks -SourceDir (Join-Path $ClaudeSource $name) `
                            -TargetDir (Join-Path $ClaudeTarget $name)
    Install-ClaudeEntries -SourceDir (Join-Path $ClaudeSource $name) `
                          -TargetDir (Join-Path $ClaudeTarget $name)
  }

  # settings.json is copied, never linked: Claude Code rewrites it whenever
  # /config changes a value, which would replace the symlink with a real file and
  # let the next run of this script discard those edits. Bootstrap only.
  $SettingsSource = Join-Path $ClaudeSource "settings.json"
  $SettingsTarget = Join-Path $ClaudeTarget "settings.json"
  if (Test-Path -LiteralPath $SettingsSource) {
    if (Test-Path -LiteralPath $SettingsTarget) {
      Write-Host "ℹ️  settings.json already exists, left untouched." -ForegroundColor Yellow
      Write-Host "   Compare by hand: Compare-Object (Get-Content '$SettingsTarget') (Get-Content '$SettingsSource')" -ForegroundColor Yellow
    } elseif ($PSCmdlet.ShouldProcess($SettingsTarget, "Copy settings.json")) {
      Copy-Item -LiteralPath $SettingsSource -Destination $SettingsTarget
      Write-Host "✅ Copied settings.json (copy, not link)" -ForegroundColor Green
    }
  }
}

# ---------- Put repo\bin on the PATH -----------------------------------------
# The commands in bin\ are put on the PATH where they are, rather than linked
# into a bin directory somewhere else: a symlink needs Developer Mode or an
# elevated shell, and a PATH entry needs neither.
#
# One entry serves both shells. PowerShell resolves claude-sessions.ps1 when you
# type `claude-sessions`, even though .PS1 is not in PATHEXT, and Git Bash reads
# the Windows PATH and runs the extension-less Bash twin sitting next to it.
# Linux is the other way round: scripts/setup.sh links the Bash halves into
# ~/.local/bin, which the zsh config already puts on PATH.
if (Test-Path -LiteralPath $BinSource) {
  Write-Host "🔧 Putting $BinSource on the user PATH" -ForegroundColor Cyan
  Add-UserPathEntry -Directory $BinSource
} else {
  Write-Warning "⚠️ Command folder not found: $BinSource (skipping)"
}

# ---------- Link GlazeWM and Zebar ------------------------------------------
# Both apps keep runtime state next to their config (errors.log for each, plus
# Zebar's .marketplace folder), so link individual entries rather than the
# ~/.glzr directories themselves, the same way the Claude config is handled.
#
# This only sets up the config files. The machine state they depend on, the
# registry policies, the elevation flag and the two autostart entries, lives in
# scripts/setup_glazewm_windows.ps1 and has to be run separately.
if (Test-Path -LiteralPath $GlazewmSource) {
  try {
    New-SafeSymlink -LinkPath $GlazewmTarget -TargetPath $GlazewmSource
    Write-Host "✅ Linked GlazeWM config" -ForegroundColor Green
  } catch {
    Write-Warning "⚠️ GlazeWM link failed: $($_.Exception.Message)"
  }
} else {
  Write-Warning "⚠️ GlazeWM source not found: $GlazewmSource (skipping)"
}

if (Test-Path -LiteralPath $ZebarPackSource) {
  try {
    New-SafeSymlink -LinkPath $ZebarPackTarget -TargetPath $ZebarPackSource
    Write-Host "✅ Linked Zebar widget pack" -ForegroundColor Green
  } catch {
    Write-Warning "⚠️ Zebar pack link failed: $($_.Exception.Message)"
  }

  # settings.json is copied, never linked, for the same reason as Claude's:
  # Zebar rewrites it whenever a widget's "run on startup" is toggled from the
  # tray, which would either write through into the repo or replace the link
  # with a real file. Bootstrap only.
  $ZebarSettingsTarget = Join-Path $ZebarDir "settings.json"
  if (Test-Path -LiteralPath $ZebarSettings) {
    if (Test-Path -LiteralPath $ZebarSettingsTarget) {
      Write-Host "ℹ️  Zebar settings.json already exists, left untouched." -ForegroundColor Yellow
      Write-Host "   Compare by hand: Compare-Object (Get-Content '$ZebarSettingsTarget') (Get-Content '$ZebarSettings')" -ForegroundColor Yellow
    } else {
      Ensure-ParentDir -Path $ZebarSettingsTarget
      if ($PSCmdlet.ShouldProcess($ZebarSettingsTarget, "Copy Zebar settings.json")) {
        Copy-Item -LiteralPath $ZebarSettings -Destination $ZebarSettingsTarget
        Write-Host "✅ Copied Zebar settings.json (copy, not link)" -ForegroundColor Green
      }
    }
  }
} else {
  Write-Warning "⚠️ Zebar pack not found: $ZebarPackSource (skipping)"
}

Write-Host "🎉 Setup complete!" -ForegroundColor Green
Write-Host "ℹ️  GlazeWM also needs system setup (autostart, registry policies):" -ForegroundColor Yellow
Write-Host "   scripts\setup_glazewm_windows.ps1   (run elevated)" -ForegroundColor Yellow
