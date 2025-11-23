<#
.SYNOPSIS
  Create Windows symlinks for your dotfiles:
  - %LOCALAPPDATA%\nvim  →  <repo>\nvim
  - %APPDATA%\bat  →  <repo>\bat
  - For each file in <repo>\powershell\ →  $HOME\Documents\PowerShell\
    * Special-case: Microsoft.PowerShell_profile.ps1 → $PROFILE

.DESCRIPTION
  - Safe to re-run. Cleans existing targets when necessary.
  - Links directories for nvim and bat; files for PowerShell.
  - If symlink creation fails (no admin / Developer Mode), shows a helpful hint.
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
$PwshRepoDir     = Join-Path $RepoRoot "powershell"

# Key user paths
$NvimTarget      = Join-Path $env:LOCALAPPDATA "nvim"
$BatTarget       = Join-Path $env:APPDATA "bat"
$ConfigDir       = Join-Path $HOME ".config"
$DeltaTarget     = Join-Path $ConfigDir "delta"
$LazygitTarget   = Join-Path $env:LOCALAPPDATA "lazygit"
$UserPwshDir     = Split-Path -Parent $PROFILE  # typically: $HOME\Documents\PowerShell
$ProfileTarget   = $PROFILE                     # exact host-specific profile path

Write-Host "🔗 Dotfiles setup" -ForegroundColor Cyan
Write-Host "  Repo root:  $RepoRoot"
Write-Host "  Neovim:     $NvimSource  →  $NvimTarget"
Write-Host "  Bat:        $BatSource  →  $BatTarget"
Write-Host "  Delta:      $DeltaSource  →  $DeltaTarget"
Write-Host "  Lazygit:    $LazygitSource  →  $LazygitTarget"
Write-Host "  PS folder:  $PwshRepoDir  →  $UserPwshDir (files only)"

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

Write-Host "🎉 Setup complete!" -ForegroundColor Green
