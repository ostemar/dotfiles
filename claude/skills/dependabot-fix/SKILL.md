---
name: dependabot-fix
description: Fix open Dependabot alerts that have no Dependabot PR (usually transitive dependencies) with one verified PR per repo - lockfile refresh within existing ranges first, overrides only for what remains. Opens the PRs, does not merge them. Use when asked to "fix the dependabot alerts", "patch the advisories", or when /dependabot-status shows alerts with no PR.
---

# /dependabot-fix

Read `../dependabot-status/reference.md` first: the repos, the gate, the
rules and the traps (exact-pin overrides, mkcert, zsh).

## Which alerts

Open, not withdrawn, with a patched version, and not covered by an open
Dependabot PR (merge that PR instead: `/dependabot-merge`). A withdrawn
advisory or one with no fix is reported, not worked around.

## Per repo: one subagent each, in parallel

Brief each subagent with the repo, the alert list (package, vulnerable range,
first patched version) and the reference file's path. Each one:

1. Clones into the scratchpad, branches `deps-alerts` from `main`, runs the
   gate on `main` for a baseline.
2. **Refreshes within existing ranges first**: `pnpm update` / `npm update`,
   `cargo update -p <crate>`, `go get <mod>@<patched>` for the parent that
   pulls the package in (`pnpm why`, `cargo tree -i`, `go mod why`).
3. Only for what is still vulnerable: raise stale overrides and add new ones
   in the manifest's existing style, as floors (`"pkg@<X": "^X"`). Cargo has
   no overrides; a transitive crate that cannot move without a parent's major
   is reported, not forced.
4. Keeps any direct-dependency update that breaks the gate (a new lint rule,
   a type change) at its old version, and reports it.
5. Proves every alerted package now resolves to a patched version (lockfile
   grep), runs the gate, compares with the baseline.
6. Commits, pushes, opens one PR with a short body saying what ran. Does not
   merge. Reports: PR URL, updates vs overrides, gate results against
   baseline, anything left and why.

## Output

One line per repo: PR link, alerts it clears, what it could not clear. Then
ask whether to merge them (as `/dependabot-merge` step 3). After a merge,
re-list alerts: the rescan can raise new ones.

Notify as `reference.md` describes if PRs are waiting on the user.
