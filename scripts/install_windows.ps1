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

function Install-PackageSafe {
  param([string]$PackageName)

  if (-not $PackageName) { return }

  Write-Host "`n→ Checking $PackageName..."

  if ((Test-ChocoInstalled -Name $PackageName) -or (Test-WingetInstalled -Name $PackageName)) {
    Write-Host "✅ $PackageName already installed"
    return
  }

  if (Get-Command choco -ErrorAction SilentlyContinue) {
    Write-Host "Installing $PackageName (Chocolatey)..."
    choco install $PackageName -y --no-progress
    if ($LASTEXITCODE -eq 0) { return }
    Write-Warning "⚠️ Chocolatey failed for $($PackageName). Will try Winget if available."
  }

  if (Get-Command winget -ErrorAction SilentlyContinue) {
    if ($PackageName -match "\.") {
      Write-Host "Installing $PackageName (Winget by Id)..."
      winget install --id $PackageName -e --accept-source-agreements --accept-package-agreements
    } else {
      Write-Host "Installing $PackageName (Winget by Name)..."
      winget install --name $PackageName -e --accept-source-agreements --accept-package-agreements
    }
    if ($LASTEXITCODE -eq 0) { return }
  }

  Write-Warning "❌ Failed to install $($PackageName). Please install it manually."
}

# ---------- Install Windows packages ----------------------------------------
if (Test-Path $PKG_FILE) {
  $packages = Get-Content $PKG_FILE | Where-Object { $_ -and $_ -notmatch '^\s*#' } | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
  foreach ($pkg in $packages) {
    Install-PackageSafe -PackageName $pkg
  }
} else {
  Write-Warning "⚠️ No package list found at $($PKG_FILE)"
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
