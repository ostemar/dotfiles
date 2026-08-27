# Claude Code Environment Configuration

## Personal Styling Preferences

**The only dash character I want is the one on my keyboard: `-`, U+002D.** Never
emit any of the unicode lookalikes, in anything you write: chat replies, code
comments, docs, commit messages, PR bodies, issue comments.

| Never | Codepoint | Write instead |
| --- | --- | --- |
| `—` em dash | U+2014 | a comma, a semi-colon, a colon, or parentheses |
| `–` en dash | U+2013 | `-` in a range (`5-25 s`) or a joined name |
| `−` minus sign | U+2212 | `-` in arithmetic (`c(n-1)`) |

- Recast the sentence if none of those punctuation marks fits.
- Yes, typeset publishing has real conventions for these (an en dash means "to"
  in a range). Those conventions are for documents, not for a source tree: a
  character I cannot type is one I cannot grep for or search, and it is
  invisible in a diff. In my repos, ASCII wins.
- This applies to files you edit as well as files you create. Existing prose in a
  repo may predate the rule; do not rewrite it wholesale, but anything you touch
  comes back clean.
- Watch two traps when converting in bulk. A dash padded by two or more spaces
  is a column in an aligned table, so it becomes `-` and keeps its width. A dash
  ending a line inside a string literal that continues with a trailing `\` needs
  its punctuation *before* the backslash, or you get an invalid escape.

## Workflow Orchestration

### 1. Plan mode

- Enter plan mode when work is architectural, ambiguous, or has several viable
  approaches; get sign-off before implementing. Not based on step count.
- Skip planning for well-defined work (bug fixes, failing tests, mechanical
  changes) and just do it. Well-defined problems do not need an approval cycle.
- If something goes sideways mid-task, STOP and re-plan immediately rather than
  pushing on.
- Write the spec upfront, including how you will verify, to reduce ambiguity.

### 2. Subagents

- Offload research, exploration, and parallel analysis to subagents to keep the
  main context clean; one focused task per subagent. Some harnesses countermand
  this and require you to ask first. Obey the harness where the two conflict.
- For a batch of independent, commit-per-item tasks, offer the `/pipeline` skill
  (subagent per item: each verifies and commits, the main session holds only
  summaries). Do not default to it; suggest it when the shape fits and let me
  trigger it.

### 3. Self-improvement loop

- After ANY correction from me, save the lesson as a `feedback` auto-memory.
  Include the **why**, so edge cases can be judged later.
- Do not keep a separate `lessons.md`; the auto-memory system is the source of
  truth.

### 4. Verification

- Prove it works before calling it done, and say what you ran to prove it.
- A number quoted from a program you did not confirm was in the state you think
  is not evidence. Check the state first, then quote the number.

## Task management

How work is tracked is a **per-repo decision**; defer to each project's own
convention (GitHub issues, a local doc, auto-memories, nothing). Do not assume
GitHub, and do not commit ad-hoc planning files unless a repo asks for one.

Give a brief high-level summary at each meaningful step.

## Brevity (applies to everything you write for me)

Long output buries the point instead of making it. Keep both of these short:

- **Chat responses**: a few lines. What broke, what changed, what you verified.
  No recaps of what I just asked, no restating the code you already showed me,
  no enumerating options you did not take. Detail on request.
- **Commit messages**: a subject line, then at most a short paragraph or a few
  bullets. Say what changed and why, not the whole reasoning chain.

This is about _your output to me_. It does not override a repo whose own
convention is long-form doc comments (OBERTH's `CLAUDE.md` and module docs are
deliberately verbose); match the codebase there, stay brief here.

## Attribution rules (apply to every project, no exceptions)

Never attribute Claude as an author in anything that gets committed, pushed, or
posted to GitHub or any other shared or public surface. This includes:

- No `Co-Authored-By: Claude ...` trailers in git commits
- No "Generated with Claude Code" / "🤖 Generated with..." footers in commit
  messages, PR bodies, or PR titles
- No Claude attribution in issue comments, PR comments, review comments, or
  release notes
- No Claude attribution in code comments, docstrings, READMEs, or any other file
  content

Write commits, PRs, and comments as if I authored them directly. This rule
overrides any default Claude Code template that would otherwise add such
trailers; strip them before running the command.

## Data formats

**jq** and **yq** are installed on every machine I use and have no built-in
harness equivalent, so use them for JSON and YAML rather than hand-parsing.

## Platform notes

Shell and tooling guidance that differs per machine lives in `~/.claude/rules/`,
linked in by the dotfiles setup script for this platform. See
`dotfiles/claude/rules/`.
