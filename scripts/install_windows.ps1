<#
.SYNOPSIS
  Bootstrap Windows dev environment:
  - Installs packages via Chocolatey (preferred) or Winget (fallback)
  - Installs PowerShell modules (CurrentUser scope)
  - Optional: runs setup.ps1 to create symlinks
  - Safe to re-run

.PARAMETER RunSetup
  If provided, will run setup.ps1 at the end (for symlinks/profile)

.PARAMETER SetupPath
  Optional custom path to setup.ps1 (defaults to ..\scripts\setup.ps1)
#>

param(
  [switch]$RunSetup,
  [string]$SetupPath
)

# ---------- Paths ------------------------------------------------------------
$SCRIPT_DIR  = Split-Path -Parent $MyInvocation.MyCommand.Path
$ROOT_DIR    = Split-Path -Parent $SCRIPT_DIR
$PKG_DIR     = Join-Path $ROOT_DIR "packages"
$PKG_FILE    = Join-Path $PKG_DIR "windows.txt"
$MODULE_FILE = Join-Path $PKG_DIR "powershell_modules.txt"

if (-not $SetupPath) {
  $SetupPath = Join-Path $SCRIPT_DIR "setup.ps1"
}

Write-Host "📦 Starting Windows environment setup..." -ForegroundColor Cyan

# ---------- Ensure Chocolatey or Winget exists ------------------------------
function Install-Chocolatey {
  Write-Host "🔸 Chocolatey not found. Installing..."
  Set-ExecutionPolicy Bypass -Scope Process -Force
  [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
  Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
  $refresh = Join-Path $env:ChocolateyInstall "bin\refreshenv.ps1"
  if (Test-Path $refresh) { . $refresh }
}

if ((-not (Get-Command choco -ErrorAction SilentlyContinue)) -and (-not (Get-Command winget -ErrorAction SilentlyContinue))) {
  Install-Chocolatey
}

# ---------- Helpers ----------------------------------------------------------
function Test-ChocoInstalled {
  param([string]$Name)
  if (-not (Get-Command choco -ErrorAction SilentlyContinue)) { return $false }
  $out = choco list --local-only --exact $Name 2>$null
  return ($out -match "^\s*$([regex]::Escape($Name))\s")
}

function Test-WingetInstalled {
  param([string]$Name)
  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { return $false }
  if ($Name -match "\.") {
    $idCheck = winget list --exact --id $Name 2>$null
    if (($LASTEXITCODE -eq 0) -and $idCheck) { return $true }
  }
  $nameCheck = winget list --name $Name 2>$null
  return (($LASTEXITCODE -eq 0) -and $nameCheck)
}

function Install-WithChoco {
  param([string]$PackageName)
  if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Warning "⚠️ Chocolatey not available for $PackageName"
    return $false
  }
  Write-Host "Installing $PackageName (Chocolatey)..."
  choco install $PackageName -y --no-progress
  return ($LASTEXITCODE -eq 0)
}

function Install-WithWinget {
  param([string]$PackageName)
  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Warning "⚠️ Winget not available for $PackageName"
    return $false
  }
  if ($PackageName -match "\.") {
    Write-Host "Installing $PackageName (Winget by Id)..."
    winget install --id $PackageName -e --accept-source-agreements --accept-package-agreements
  } else {
    Write-Host "Installing $PackageName (Winget by Name)..."
    winget install --name $PackageName -e --accept-source-agreements --accept-package-agreements
  }
  return ($LASTEXITCODE -eq 0)
}

function Install-PackageSafe {
  param(
    [string]$PackageName,
    [string]$Manager = ""
  )

  if (-not $PackageName) { return }

  Write-Host "`n-> Checking $PackageName..."

  if ((Test-ChocoInstalled -Name $PackageName) -or (Test-WingetInstalled -Name $PackageName)) {
    Write-Host "OK $PackageName already installed"
    return
  }

  $success = $false

  switch ($Manager.ToLower()) {
    "choco" {
      $success = Install-WithChoco -PackageName $PackageName
    }
    "winget" {
      $success = Install-WithWinget -PackageName $PackageName
    }
    default {
      # Default: try choco first, fallback to winget
      $success = Install-WithChoco -PackageName $PackageName
      if (-not $success) {
        Write-Warning "Chocolatey failed for $PackageName. Trying Winget..."
        $success = Install-WithWinget -PackageName $PackageName
      }
    }
  }

  if (-not $success) {
    Write-Warning "Failed to install $PackageName. Please install it manually."
  }
}

# ---------- Install Windows packages ----------------------------------------
# Format: "manager package" (e.g., "choco 7zip" or "winget Microsoft.VisualStudioCode")
# If no manager specified, defaults to choco with winget fallback
if (Test-Path $PKG_FILE) {
  $lines = Get-Content $PKG_FILE | Where-Object { $_ -and $_ -notmatch '^\s*#' } | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
  foreach ($line in $lines) {
    $parts = $line -split '\s+', 2
    if ($parts.Count -eq 2 -and $parts[0] -match '^(choco|winget)$') {
      $manager = $parts[0]
      $pkg = $parts[1]
    } else {
      $manager = ""
      $pkg = $line
    }
    Install-PackageSafe -PackageName $pkg -Manager $manager
  }
} else {
  Write-Warning "No package list found at $PKG_FILE"
}

# ---------- Install PowerShell modules --------------------------------------
if (Test-Path $MODULE_FILE) {
  Write-Host "`n🧩 Installing PowerShell modules..."
  $modules = Get-Content $MODULE_FILE | Where-Object { $_ -and $_ -notmatch '^\s*#' } | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
  foreach ($module in $modules) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
      Write-Host "Installing PowerShell module: $module"
      try {
        Install-Module -Name $module -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
      } catch {
        Write-Warning "⚠️ Failed to install $($module): $($_.Exception.Message)"
      }
    } else {
      Write-Host "✅ Module $module already installed"
    }
  }
} else {
  Write-Warning "⚠️ No PowerShell module list found at $($MODULE_FILE)"
}

# ---------- Optionally run setup.ps1 (symlinks/profile) ---------------------
if ($RunSetup) {
  if (Test-Path $SetupPath) {
    Write-Host "`n🔗 Running setup script: $SetupPath"
    try {
      & $SetupPath
    } catch {
      Write-Warning "⚠️ setup.ps1 failed: $($_.Exception.Message)"
    }
  } else {
    Write-Warning "⚠️ Setup script not found at $($SetupPath)"
  }
}

Write-Host "`n🎉 Windows setup complete!" -ForegroundColor Green
