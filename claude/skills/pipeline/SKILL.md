---
name: pipeline
description: Run a batch of independent, well-scoped tasks as a subagent-per-item pipeline — one subagent per item, each verifies and commits, the main session only holds short summaries. Use when handed a LIST of independent items that each end in a natural checkpoint (a commit) and you want to keep the orchestrating context lean. Triggers — "run these as a pipeline", "subagent per item", "one subagent at a time and commit each", "batch these", or proactively offer it when the user hands over several independent, commit-per-item tasks. NOT for single tasks, tightly-coupled work, or exploratory/ambiguous work where the plan is the deliverable.
user-invocable: true
---

# /pipeline — subagent-per-item batch execution

Run a batch of independent tasks by dispatching **one focused subagent per
item**, sequentially. Each subagent does the heavy reading/editing in its own
context, verifies, commits, and returns a short summary — so the orchestrating
(main) session stays lean and fast instead of carrying every file it touches.

This is a workflow the user opts into deliberately. Don't default to it — offer
it when the shape fits, and let them trigger it.

## When this fits (and when it doesn't)

**Use it when ALL of these hold:**
- There's a **list** of items (roughly 2+), each doable in isolation.
- Items are **independent** — one doesn't need another's evolving context.
- Each ends in a **natural checkpoint** (usually a commit).
- Keeping the main session's context lean is worth the cost of each subagent
  re-reading files cold.

**Don't use it for:**
- A single task, or tightly-coupled work that must share evolving state.
- Exploratory/ambiguous work where the *plan itself* is the deliverable (plan
  first instead).
- Anything where parallel edits to one working tree would be needed — see the
  sequential rule below.

## The procedure

### 1. Triage the items first
Split the batch into two buckets and confirm the split with the user:
- **Mechanical / hands-off** — well-defined, one right answer. Subagent
  implements → verifies → **commits** autonomously.
- **Taste / approval-gated** — cosmetic, wording, or design-flavoured choices
  the user may want a say in. Subagent drafts it **uncommitted** and produces a
  screenshot/artifact; the user approves *before* it commits.

Also settle the review cadence for the mechanical bucket: sanity-check each
diff, or run them back-to-back and review at the end. (Ask; both are valid.)

### 2. Run SEQUENTIALLY, never in parallel
All items share one working tree and each ends in a commit. Parallel subagents
would collide on files and on the git index. Dispatch one, wait for it, then the
next. (Parallel is only safe with git-worktree isolation, which complicates
committing straight to a branch — not worth it for a normal polish batch.)

### 3. Each subagent gets a self-contained contract
Because a subagent starts cold, its prompt must carry everything. Spell out:
- **Check git first** — `git status` + `git log`; the user may run **concurrent
  sessions**, so if there are unexpected uncommitted changes that aren't the
  task's, STOP and report rather than committing over them.
- The task, the relevant files, and the project's invariants it must not break
  (e.g. determinism guards, "presentation-only", test names to keep green).
- **Verify before committing** — build + full test suite + any guard tests;
  actually exercise runtime changes where practical.
- **Commit conventions** — concise imperative subject in the repo's style,
  scoped to just this item, and **no AI/Claude attribution of any kind** (strip
  any default co-author/generated-with trailer).
- **Report back a SHORT summary** — files changed, what/why, test results
  (name the guards), commit hash + subject. Raw data; it's a tool result to the
  orchestrator, not a human message.

### 4. Taste items: draft → show → approve → commit
For approval-gated items, instruct the subagent to leave the change
**uncommitted** and produce the evidence (screenshot to a known path, etc.).
Bring it to the user (copying preview files somewhere easy to open helps — a
deep temp path is annoying to navigate). Only after they approve do you commit
(either you commit directly, or send the subagent follow-up tweaks first). If
they want changes, iterate before committing.

### 5. Orchestrator's job between items
- Keep a lightweight ledger of the batch (prose is fine if no todo tool).
- Lightly review each committed diff — "a subagent committed" is not "verified
  good". Look at the riskiest change yourself (e.g. anything touching a
  determinism-critical or shared file).
- Report a clean summary at the end: a table of item → commit → what, plus the
  verification state and anything deferred.

## Gotchas learned

- **A finished subagent can't always be resumed** (its transcript may be gone).
  To iterate on its work, spawn a **fresh** subagent that reads the still-
  **uncommitted** change in the working tree — don't rely on resuming.
- **Clean up preview/scratch artifacts** (e.g. `_preview/` folders copied out for
  the user) once a decision is made, so nothing stray gets committed.
- **Push only when asked.** Fetch first and confirm the local-vs-remote range
  before pushing; the concurrent-session caveat applies here too.
- **Scope creep in subagents** — a subagent may "improve" wording or refactor
  beyond the ask. Flag such extras to the user rather than swallowing them.
