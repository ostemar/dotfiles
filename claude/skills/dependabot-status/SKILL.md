---
name: dependabot-status
description: Summarise Dependabot across all of the user's repos - open alerts by severity, open Dependabot PRs and whether their checks pass, and what needs the user. Read-only. Use when asked for dependabot status, "any dependabot alerts", "what does dependabot want", or as the first step of a scheduled dependency run.
---

# /dependabot-status

Read-only. Never merge, comment, push or change a setting.

Read `reference.md` in this skill's directory first: it says which repos, the
queries, and how to tell security PRs from version PRs.

## Steps

1. Find the repos (or take the ones the user named).
2. For each, in one pass: open alerts (count by severity, package names) and
   open Dependabot PRs (kind, checks, mergeable, age). Skip withdrawn
   advisories in the counts but mention them.
3. Do not work out which PR covers which alert: that needs a clone and an
   install (see the reference). Say "N alerts, M Dependabot PRs open" and let
   `/dependabot-merge` settle coverage. A repo with alerts and no Dependabot
   PR at all is a job for `/dependabot-fix`.

## Output

One table, repos with nothing open folded into a single line at the end:

| Repo | Alerts (crit/high/med/low) | Dependabot PRs | Needs |
| --- | --- | --- | --- |

In the PRs column give each PR its number, kind (security, group, breaking,
single) and checks (passing, failing, none). "Needs" is one phrase: "merge
#12, #14", "breaking #5 to read", "#3 has no checks: run locally", "fix 3
alerts with no PR", "check failing on #9".

Then at most three lines of what to do next, naming `/dependabot-merge` or
`/dependabot-fix` where they apply. Keep it short: the reader is deciding
what to spend a weekend hour on.

If anything needs the user, notify as `reference.md` describes.
