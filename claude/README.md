# Claude Code config

Personal Claude Code configuration, linked into `~/.claude` by
`scripts/setup.ps1` (Windows) and `scripts/setup.sh` (Linux/WSL).

No plugin manifest, no marketplace. Those exist to distribute config to people
who do not have this repo. Symlinks do the same job here with no metadata.

## Layout

| Repo path | Linked to | Loaded when |
| --- | --- | --- |
| `CLAUDE.md` | `~/.claude/CLAUDE.md` | every session, every project |
| `rules/*.md` | `~/.claude/rules/` | session start (or on matching file, if the rule has `paths:`) |
| `skills/<name>/SKILL.md` | `~/.claude/skills/<name>/` | listed at startup, body loads on `/<name>` |
| `agents/<name>.md` | `~/.claude/agents/` | when Claude delegates or you @-mention it |
| `themes/*.json` | `~/.claude/themes/` | session start, selected by `theme` in settings |
| `statusline.js` | `~/.claude/statusline.js` | every status line render (see below) |
| `settings.json` | copied, not linked | session start (see below) |

`~/.claude` also holds runtime state Claude Code writes for itself
(`projects/`, `sessions/`, `history.jsonl`, `.credentials.json`, `plugins/`).
That is why the setup scripts link individual entries rather than the whole
directory.

## Platform-gated rules

A rule named `<name>.windows.md` is linked only by `setup.ps1`;
`<name>.linux.md` only by `setup.sh`. Anything else is linked everywhere. Use
this for guidance that is wrong on the other machine, such as which shell tool
to prefer.

## settings.json is copied, not linked

Claude Code rewrites `~/.claude/settings.json` itself whenever `/config` changes
a value such as the theme. A symlink there is likely to be replaced by a real
file, and the next `setup` run would then discard those changes. So the scripts
copy it only when `~/.claude/settings.json` does not exist yet, to bootstrap a
new machine, and otherwise leave it alone.

To pick up changes made on one machine, diff and copy by hand:

```bash
diff ~/.claude/settings.json claude/settings.json
```

Never commit `~/.claude/.credentials.json`.

## Status line

`settings.json` points `statusLine` at `node "$HOME/.claude/statusline.js"`.
Claude Code runs that command through the shell, Git Bash on Windows and the
login shell on Linux, so `$HOME` expands on both and the one string needs no
per-machine path.

The script pipes the status line payload to `ccusage statusline` and drops the
cost segments before printing, leaving the model and the context usage:

```
🤖 Opus 5 | 🧠 59,180 (6%)
```

ccusage has no flag to hide those segments, hence the wrapper. It needs `node`
and `npx` on PATH, and it prints nothing at all if ccusage fails, which leaves
an empty status line rather than an error in the bar.

## Hooks

There is no auto-loaded `~/.claude/hooks/` directory. A hook only runs if it is
declared under `"hooks"` in `settings.json`, or in the `hooks:` frontmatter of a
skill or agent. If a hook script is added here later, it needs a matching
`settings.json` entry to do anything.

## Adding a skill

```bash
mkdir -p claude/skills/my-skill
```

`claude/skills/my-skill/SKILL.md` needs only a `description`; the directory name
becomes `/my-skill`. Add `disable-model-invocation: true` to keep Claude from
loading it on its own. Then re-run the setup script for this platform.

A skill body loads only when the skill is invoked. Instructions that must apply
to every session belong in `rules/` instead.
