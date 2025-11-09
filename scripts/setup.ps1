<#
.SYNOPSIS
  Create Windows symlinks for your dotfiles:
  - %LOCALAPPDATA%\nvim  →  <repo>\nvim
  - For each file in <repo>\powershell\ →  $HOME\Documents\PowerShell\
    * Special-case: Microsoft.PowerShell_profile.ps1 → $PROFILE

.DESCRIPTION
  - Safe to re-run. Cleans existing targets when necessary.
  - Links only files; never directories.
  - If symlink creation fails (no admin / Developer Mode), shows a helpful hint.

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
$PwshRepoDir     = Join-Path $RepoRoot "powershell"

# Key user paths
$NvimTarget      = Join-Path $env:LOCALAPPDATA "nvim"
$UserPwshDir     = Split-Path -Parent $PROFILE  # typically: $HOME\Documents\PowerShell
$ProfileTarget   = $PROFILE                     # exact host-specific profile path

Write-Host "🔗 Dotfiles setup" -ForegroundColor Cyan
Write-Host "  Repo root:  $RepoRoot"
Write-Host "  Neovim:     $NvimSource  →  $NvimTarget"
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

# ---------- Link Neovim ------------------------------------------------------
try {
  New-SafeSymlink -LinkPath $NvimTarget -TargetPath $NvimSource
  Write-Host "✅ Linked Neovim config" -ForegroundColor Green
} catch {
  Write-Warning "⚠️ Neovim link failed: $($_.Exception.Message)"
  throw
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
