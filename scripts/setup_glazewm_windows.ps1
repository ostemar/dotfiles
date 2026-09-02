<#
.SYNOPSIS
  Windows system setup for GlazeWM and Zebar. Everything here is machine state
  that a symlink cannot express: registry policies, the elevation flag, and the
  two autostart entries.

.DESCRIPTION
  Windows only. scripts/setup.ps1 links the config files; this script makes the
  OS cooperate with them. Safe to re-run, and supports -WhatIf.

  What it does, and why each piece is needed:

  1. RUNASADMIN on glazewm.exe
     GlazeWM's keyboard hook cannot see input while a window from an elevated
     process has focus, so without this a modifier key-up can be missed and you
     end up stuck with bare keys firing WM commands.

  2. NoWinKeys=1 (HKCU)
     With the Windows key as the modifier, a win+ combo leaves the Start menu
     open afterwards. Open GlazeWM bug, glzr-io/glazewm#1215. Applied always.

     Note there is deliberately no DisableLockWorkstation option here. That
     policy frees a plain win+l binding, but disables the LockWorkStation API
     outright, leaving no way to lock the machine at all. config.yaml sidesteps
     the whole problem by binding focus to win+alt instead: Windows hotkeys
     match their modifier set exactly, so Win+Alt+L never reaches winlogon's
     Win+L handler and both bindings coexist.

  3. Scheduled task 'GlazeWM', at logon, RunLevel Highest
     GlazeWM's own tray option "Run on system startup" writes a
     ...\CurrentVersion\Run entry, and Run entries launch with the filtered,
     non-elevated token. Combined with (1) that means a UAC prompt every logon
     or a silent failure. A scheduled task is the only way to autostart it
     elevated and silently. Leave the tray option OFF or you get two instances.

  4. Startup-folder shortcut for Zebar
     Zebar is deliberately NOT in GlazeWM's startup_commands. A child of the
     elevated GlazeWM inherits elevation, and an elevated Zebar breaks its own
     systray widget: the tray works by receiving WM_COPYDATA broadcasts from
     other apps, and UIPI blocks messages from a lower integrity level to a
     higher one. A Startup-folder shortcut keeps Zebar at normal integrity.

.PARAMETER SkipScheduledTask
  Skip registering the GlazeWM autostart task. That step needs elevation; use
  this to run the rest without a UAC prompt.

.PARAMETER WhatIf
  Dry-run. Shows what would change without changing anything.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [switch]$SkipScheduledTask
)

$ErrorActionPreference = 'Stop'

$GlazeExe = Join-Path $env:ProgramFiles 'glzr.io\GlazeWM\glazewm.exe'
$ZebarExe = Join-Path $env:ProgramFiles 'glzr.io\Zebar\zebar.exe'
$TaskName = 'GlazeWM'

Write-Host "🪟 GlazeWM / Zebar Windows setup" -ForegroundColor Cyan
Write-Host "  GlazeWM: $GlazeExe"
Write-Host "  Zebar:   $ZebarExe"

# ---------- Helpers ----------------------------------------------------------
function Test-IsElevated {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal $identity
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Set-RegistryValue {
  <#
    Idempotent DWORD write. Reports whether it changed anything so a re-run
    reads as a no-op rather than looking like it did work it did not do.
  #>
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][int]$Value,
    [Parameter(Mandatory)][string]$Reason
  )

  $current = $null
  if (Test-Path -LiteralPath $Path) {
    $current = (Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue).$Name
  }

  if ($current -eq $Value) {
    Write-Host "✅ $Name already $Value ($Reason)" -ForegroundColor DarkGray
    return
  }

  if ($PSCmdlet.ShouldProcess("$Path\$Name", "Set to $Value")) {
    if (-not (Test-Path -LiteralPath $Path)) {
      New-Item -Path $Path -Force | Out-Null
    }
    New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value `
      -PropertyType DWord -Force | Out-Null
    Write-Host "✅ Set $Name = $Value ($Reason)" -ForegroundColor Green
  }
}

# ---------- Preflight --------------------------------------------------------
if (-not (Test-Path -LiteralPath $GlazeExe)) {
  throw "GlazeWM not found at '$GlazeExe'. Install it first (winget glzr-io.glazewm)."
}
if (-not (Test-Path -LiteralPath $ZebarExe)) {
  Write-Warning "⚠️ Zebar not found at '$ZebarExe'. Skipping its autostart shortcut."
}

# ---------- 1. Run GlazeWM elevated -----------------------------------------
$LayersKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
$existingLayer = $null
if (Test-Path -LiteralPath $LayersKey) {
  $existingLayer = (Get-ItemProperty -LiteralPath $LayersKey -Name $GlazeExe -ErrorAction SilentlyContinue).$GlazeExe
}

if ($existingLayer -and $existingLayer -match 'RUNASADMIN') {
  Write-Host "✅ glazewm.exe already flagged RUNASADMIN" -ForegroundColor DarkGray
} elseif ($PSCmdlet.ShouldProcess($GlazeExe, 'Set RUNASADMIN compatibility flag')) {
  if (-not (Test-Path -LiteralPath $LayersKey)) {
    New-Item -Path $LayersKey -Force | Out-Null
  }
  # Preserve any other layers already set on the exe rather than clobbering.
  $layerValue = if ($existingLayer) { "$existingLayer RUNASADMIN" } else { '~ RUNASADMIN' }
  New-ItemProperty -LiteralPath $LayersKey -Name $GlazeExe -Value $layerValue `
    -PropertyType String -Force | Out-Null
  Write-Host "✅ Flagged glazewm.exe to always run as administrator" -ForegroundColor Green
}

# ---------- 2 & 3. Keyboard policies ----------------------------------------
Set-RegistryValue `
  -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer' `
  -Name 'NoWinKeys' -Value 1 `
  -Reason 'stop the Start menu opening after win+ combos'

# Win+L stays with Windows. config.yaml binds focus to win+alt precisely so it
# does not have to fight for it. If a machine still carries
# DisableLockWorkstation=1 from an older setup, say so, because it silently
# leaves the machine unlockable.
$LockPolicyKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\System'
$lockDisabled = (Get-ItemProperty -LiteralPath $LockPolicyKey -Name 'DisableLockWorkstation' -ErrorAction SilentlyContinue).DisableLockWorkstation

if ($lockDisabled -eq 1) {
  Write-Warning @"
⚠️ DisableLockWorkstation=1 is set on this machine, so it cannot be locked at
   all: not by Win+L, not by the LockWorkStation API, not from the
   Ctrl+Alt+Del screen. This setup no longer needs it, since focus is bound to
   win+alt. Clear it and sign out and back in:
     reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System" /v DisableLockWorkstation /t REG_DWORD /d 0 /f
"@
} else {
  Write-Host "✅ Win+L still locks the machine (focus is bound to win+alt)" -ForegroundColor DarkGray
}

# ---------- 4. GlazeWM autostart (scheduled task) ---------------------------
if ($SkipScheduledTask) {
  Write-Host "⏭️  Skipped scheduled task (-SkipScheduledTask)" -ForegroundColor DarkGray
} elseif (-not (Test-IsElevated)) {
  Write-Warning @"
⚠️ Not elevated, so the '$TaskName' autostart task was not registered.
   Re-run this script from an elevated PowerShell, or pass -SkipScheduledTask
   to silence this. Everything else above has been applied.
"@
} else {
  $userId = "$env:USERDOMAIN\$env:USERNAME"

  $action = New-ScheduledTaskAction -Execute $GlazeExe

  # Short delay so the shell has settled before GlazeWM starts.
  $trigger = New-ScheduledTaskTrigger -AtLogOn -User $userId
  $trigger.Delay = 'PT10S'

  $principal = New-ScheduledTaskPrincipal -UserId $userId `
    -LogonType Interactive -RunLevel Highest

  # The battery flags matter on a laptop: the defaults refuse to start on
  # battery and kill the task when you unplug. ExecutionTimeLimit zero stops
  # Windows terminating it after three days.
  $settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -MultipleInstances IgnoreNew

  if ($PSCmdlet.ShouldProcess($TaskName, "Register logon task (elevated) for $userId")) {
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
      -Principal $principal -Settings $settings -Force | Out-Null

    $task = Get-ScheduledTask -TaskName $TaskName
    if ($task.Principal.RunLevel -ne 'Highest') {
      throw "Task '$TaskName' registered but RunLevel is '$($task.Principal.RunLevel)', not 'Highest'."
    }
    Write-Host "✅ Registered task '$TaskName' (at logon, elevated, $userId)" -ForegroundColor Green
  }
}

# ---------- 5. Zebar autostart (Startup folder, normal integrity) -----------
if (Test-Path -LiteralPath $ZebarExe) {
  $startupDir = [Environment]::GetFolderPath('Startup')
  $lnkPath = Join-Path $startupDir 'Zebar.lnk'

  $needsWrite = $true
  if (Test-Path -LiteralPath $lnkPath) {
    $shell = New-Object -ComObject WScript.Shell
    $existing = $shell.CreateShortcut($lnkPath)
    if ($existing.TargetPath -eq $ZebarExe) {
      Write-Host "✅ Zebar startup shortcut already correct" -ForegroundColor DarkGray
      $needsWrite = $false
    }
  }

  if ($needsWrite -and $PSCmdlet.ShouldProcess($lnkPath, "Create Zebar startup shortcut")) {
    $shell = New-Object -ComObject WScript.Shell
    $lnk = $shell.CreateShortcut($lnkPath)
    $lnk.TargetPath = $ZebarExe
    $lnk.WorkingDirectory = Split-Path $ZebarExe -Parent
    $lnk.Description = 'Zebar status bar (started outside GlazeWM so it stays at normal integrity)'
    $lnk.Save()

    if (-not (Test-Path -LiteralPath $lnkPath)) {
      throw "Shortcut '$lnkPath' was not created."
    }
    Write-Host "✅ Created Zebar startup shortcut" -ForegroundColor Green
  }
}

Write-Host ""
Write-Host "🎉 GlazeWM Windows setup complete." -ForegroundColor Green
Write-Host "   Registry policies apply after sign out and back in." -ForegroundColor Yellow
Write-Host "   Leave GlazeWM's tray option 'Run on system startup' OFF." -ForegroundColor Yellow
