# Shell and CLI tools (Linux)

- **Platform**: Linux (native or WSL). The Bash tool is the only shell; there is
  no PowerShell tool and no MSYS path translation, so paths and `/`-style flags
  pass through unchanged. None of the Windows-side workarounds apply here.
- My interactive shell is zsh, but the Bash tool runs bash and does not read
  `~/.zshrc`. Do not assume aliases defined there exist; on Debian and Ubuntu
  that includes `bat`, which ships as `batcat`.
- Under WSL, `/mnt/c/...` crosses the filesystem boundary and is slow. Keep
  builds and scratch files on the Linux side.
