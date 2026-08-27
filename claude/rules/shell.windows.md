# Shell and CLI tools (Windows)

- **Platform**: Windows (win32), but **default to the Bash tool** (git-bash /
  MSYS); it is the preferred shell here. Reach for the **PowerShell** tool only
  when you actually need Windows-native behaviour: running `.ps1` scripts, or CLI
  tools that take `/`-style switches (which MSYS mangles into Windows paths).
- Do not cross the streams. In the Bash tool use POSIX heredocs (`<<'EOF' ... EOF`)
  for multiline strings such as commit messages, never PowerShell here-strings
  (`@'...'@`), whose leading `@` git-bash passes through as a literal character.
  Where backslashes or other escapes are involved, write the file with Write or
  Edit instead of piping it through a shell.
