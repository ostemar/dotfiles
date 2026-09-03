<#
.SYNOPSIS
  List Claude Code sessions across ALL projects, newest first, grouped by day.

.DESCRIPTION
  Claude Code itself only lists the sessions of the current project
  (`claude --resume`, `/resume`), which is useless when you remember a
  conversation but not which repo you had open at the time. The transcripts are
  all on disk under ~/.claude/projects/<encoded-cwd>/<session-id>.jsonl, so this
  reads them directly: LastWriteTime for "when", the first real user prompt for
  "what".

  The Bash twin, bin/claude-sessions, does the same thing for Git Bash and
  Linux. Keep the two in sync when changing behaviour.

.PARAMETER Limit
  Show at most this many sessions (default 40). Alias: -n

.PARAMETER All
  Show every session. Alias: -a

.PARAMETER Pattern
  Case-insensitive filter on project path or first prompt.

.EXAMPLE
  claude-sessions
  claude-sessions -n 100
  claude-sessions dotfiles

.NOTES
  Resume one with:  cd <the project dir shown>; claude --resume <session-id>
#>

[CmdletBinding()]
param(
  [Alias('n')][int]$Limit = 40,
  [Alias('a')][switch]$All,
  [Parameter(Position = 0)][string]$Pattern
)

$ErrorActionPreference = 'Stop'

# Prompts are full of non-ASCII (Swedish text, em dashes, box drawing). Without
# this, redirecting the listing to a file or another program writes it in the
# console's legacy code page and mangles all of it.
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }

$PromptWidth = 110
# Enough to reach the first user message past any header lines, without reading
# megabytes of transcript per file.
$HeadLines = 400

$configDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
$root = Join-Path $configDir 'projects'
if (-not (Test-Path -LiteralPath $root)) {
  Write-Error "No Claude Code sessions found at $root"
  exit 1
}

function Get-FirstPrompt {
  <#
    First real user prompt of a transcript, plus the directory it ran in.

    A prompt sent with an image or other attachment arrives as content blocks
    rather than a plain string; the text blocks are the prompt. Tool results are
    blocks too and collapse to "" here, which is the point.

    Skipped: subagent sidechains (isSidechain), anything that leaves no text,
    and the wrapper text Claude Code injects for slash commands and memory
    reminders.
  #>
  param([Parameter(Mandatory)][string]$Path)

  foreach ($line in (Get-Content -LiteralPath $Path -TotalCount $HeadLines -ErrorAction SilentlyContinue)) {
    # Cheap string test first: parsing every line as JSON is what makes this slow.
    if ($line -notlike '*"type":"user"*') { continue }

    try { $entry = $line | ConvertFrom-Json } catch { continue }
    if ($entry.type -ne 'user' -or $entry.isSidechain -eq $true) { continue }

    $content = $entry.message.content
    $text = if ($content -is [string]) {
      $content
    } elseif ($content -is [System.Collections.IEnumerable]) {
      ($content | Where-Object { $_.type -eq 'text' } | ForEach-Object { $_.text }) -join ' '
    } else {
      ''
    }

    # Cut before collapsing whitespace: a prompt with a pasted file in it runs
    # to megabytes, and only the first line of it is ever shown.
    if ($text.Length -gt 800) { $text = $text.Substring(0, 800) }
    $text = ($text -replace '\s+', ' ').Trim()
    if (-not $text) { continue }
    if ($text -match '^<(local-command|command-name|user-memory)') { continue }
    if ($text.Length -gt $PromptWidth) { $text = $text.Substring(0, $PromptWidth).TrimEnd() }

    return [pscustomobject]@{
      Cwd    = if ($entry.cwd) { $entry.cwd } else { '?' }
      Prompt = $text
    }
  }
  return $null
}

# Session transcripts only: subagent transcripts live one level deeper, in
# <session-id>\subagents\agent-*.jsonl, and are part of a session rather than
# sessions of their own.
#
# LastWriteTime is last activity, which is the order the desktop app's sidebar
# uses; the first timestamp inside a file would instead order by when it started.
#
# Sorted by mtime, then by session id so that the many files sharing a timestamp
# (a bulk copy, a restore) come out in a stable order rather than whatever order
# the filesystem hands them over in.
$files = Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
  ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Filter '*.jsonl' -File -ErrorAction SilentlyContinue } |
  Sort-Object -Property @{ Expression = 'LastWriteTime'; Descending = $true },
                        @{ Expression = 'Name'; Descending = $false }

$max = if ($All) { [int]::MaxValue } else { $Limit }
$day = ''
$shown = 0

foreach ($file in $files) {
  if ($shown -ge $max) { break }

  $found = Get-FirstPrompt -Path $file.FullName
  if (-not $found) { continue }
  if ($Pattern -and ("$($found.Cwd) $($found.Prompt)" -notmatch [regex]::Escape($Pattern))) { continue }

  $thisDay = $file.LastWriteTime.ToString('yyyy-MM-dd ddd')
  if ($thisDay -ne $day) {
    $day = $thisDay
    # Plain strings down the pipeline rather than Write-Host, so the listing can
    # be piped into Select-String, Out-File or a pager like any other output.
    Write-Output ""
    Write-Output "== $day =="
  }

  Write-Output ("  {0}  {1}" -f $file.LastWriteTime.ToString('HH:mm'), $found.Cwd)
  Write-Output ("         {0}  {1}" -f $file.BaseName, $found.Prompt)
  $shown++
}

if ($shown -eq 0) {
  Write-Output "(no sessions matched)"
} else {
  Write-Output ""
}
