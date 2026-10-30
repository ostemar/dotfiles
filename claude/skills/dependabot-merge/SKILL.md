---
name: dependabot-merge
description: Review open Dependabot PRs across the user's repos (or the ones named), verify the ones that need more than a green check by running the repo's gate locally, and merge what the user approves. Use when asked to "review the dependabot PRs", "merge the dependabot PRs", or "close out dependabot".
---

# /dependabot-merge

Read `../dependabot-status/reference.md` first: the repos, the gate, what the
PR checks prove, and the rules (no force-push, merging is the user's call).

## 1) Sort every open Dependabot PR into one of three

- **Ready**: a grouped or single patch/minor update, checks green, and the
  repo's checks run its tests. Nothing to do but merge.
- **Run it first**: anything else that is green or has no checks at all. A
  breaking bump (a major, or `0.x` to `0.y`), a toolchain update (test
  runner, bundler, compiler, framework, game engine, deploy CLI), or any PR in
  a repo whose checks only build or do not exist. Read the release notes'
  breaking changes for breaking bumps.
- **Blocked**: failing checks, conflicts, or a bump the repo's config or
  `CLAUDE.md` says to hold back. Read the failing log and say why in one line.

A PR that a newer one supersedes (same package, older target) is closed by
Dependabot once the newer one lands; leave it.

## 2) Run the "run it first" PRs

In a scratchpad clone: the gate on `main`, then on each PR head
(`git fetch origin pull/<n>/head`). On each head, also note which open alerts
it clears (the reference says how). For a breaking bump, read its release
notes or changelog (`gh release view -R <upstream>`, or the CHANGELOG at the
new tag) and list the breaking changes that touch what this repo uses; none
found is a finding too. Several repos at once go to one subagent per repo,
each returning a few lines; one repo is done inline.

## 3) Ask, once

One table: PR, kind, alerts it clears, verdict, evidence (what ran, test
counts; "build only" where that is all the repo has). Then a single
question: merge the ready and verified ones, breaking ones last? An
unattended run stops here and notifies.

## 4) Merge what was approved

Per repo, groups and security PRs first, majors last, one at a time:
`gh pr merge <n> --squash --delete-branch`. When the next one is out of date,
comment `@dependabot rebase` and wait for its checks; fall back as
`reference.md` says. Never force-push.

Finish by re-listing alerts for the merged repos and saying what is still
open, and whether it is a job for `/dependabot-fix`.
