---
name: team-status
description:
  "Morning status for teams Awesome and Brilliant: Linear work in flight (plus
  legacy Jira), PR and review state, full-validation freshness, branch CI,
  develop drift and conflicts, what merged, and what is live on QA and prod. Use
  before the dailies or when asked what the teams are working on, how PRs are
  doing, or which branches are red."
metadata:
  short-description: "Team status before the dailies"
---

# Skill: Team status

Build a short, act-on-it picture of teams **Awesome** and **Brilliant** from
git, Azure DevOps and the issue tracker. The reader is the architect and team
lead reading it minutes before the dailies. Output goes in chat.

Read-only. Never queue builds, push, comment, transition issues or edit PRs.

## Inputs

- Optional team: `awesome` or `brilliant` (default: both, in separate sections,
  one per standup).
- Optional window: `since <date>` (default: previous working day 00:00, so
  Monday covers Friday).

## 1) Collect (run both in parallel)

**Git + Azure DevOps**, with the PowerShell tool (about 30 s):

```powershell
pwsh -NoProfile -File "$HOME\.claude\skills\team-status\collect.ps1" -OutFile <scratchpad>/team-status.json
```

Add `-Since <yyyy-MM-dd>` when the user gave a window. The script reads the OSR
repo it is started in, else `C:\code\OSR`; if it reports no OSR checkout, ask
the user for the path and pass `-RepoPath`. It fetches origin; it never touches
the working tree, and any branch can be checked out. Read the JSON file whole. Shape:

- `develop.pipelines[]`: latest result + `history` on develop.
- `prs[]`: active PRs newer than 90 days (`skippedOldPrs` counts the rest):
  reviewers and votes, pushes, human/bot active threads, `validation[]`,
  `buildPolicies[]`.
- `branches[]`: active-PR sources plus branches with commits in 14 days: `ahead`
  (commits) and `behind` (develop merges since the branch point), `baseDate`,
  `lastDevelopMerge`, `conflictCount`, `migrationCount`, branch `ci[]`.
- `merged[]`: PRs merged to develop in the window.
- `prod[]`: per release pipeline, what is live and whether a newer green develop
  build is waiting (`pendingMergeCount`, `pendingMigrations` for `db`).
- `qa[]`: feature branches deployed on QA envs, plus anything deployed in the
  window.

History strings read newest first: `S` succeeded, `F` failed, `P` partially
succeeded, `C` canceled. `commitsSince` / `pushesSince` count what landed on the
branch after that run.

**Tracker**: Linear first. Jira is legacy: keep reading it until the teams have
no in-flight work there, then delete the Jira block.

_Linear_ (`RPT-<n>`, all in team Reporting). The dev teams are labels in the
"Team" group (`Awesome`, `Brilliant`, `Integration`) and `label` takes one name,
so query each team separately. Use `mcp__linear-server__list_issues` with
`team: "Reporting"`, `limit: 250` and fields
`id, title, status, statusType, assignee, updatedAt, startedAt, completedAt, canceledAt, labels, parentId, url`.
There is no top-level filter: drop rows with a `parentId` (sub-issues are their
parent's to-do list; one top-level issue is one branch and one PR). Page with
`cursor` when a call returns `limit` rows.

1. In flight, per team: `label: "<Awesome|Brilliant>", state: "started"` (In
   Progress and In Review).
2. Ready queue size, per team: `label: "<team>", state: "Todo"`; count the rows,
   there is no total.
3. Moved in the window, per team:
   `label: "<team>", updatedAt: "<since yyyy-MM-dd>"`. There is no
   status-history filter and any edit moves `updatedAt`: keep rows whose
   `startedAt`, `completedAt` or `canceledAt` is in the window, plus In Review
   rows (that move has no timestamp of its own).
4. Stuck: no call. Query 1 rows with `updatedAt` older than 7 days (any edit
   resets it, so this finds fewer than the Jira query).
5. Sub-issues being worked, one call per query 1 key:
   `parentId: "<key>", state: "started"`.

Status names in the signals below are Jira's. For RPT read Developing as In
Progress, Ready for Review as In Review, Ready for development as Todo, Closed
as Done or Canceled. PRs open early and In Review is rare, so take review state
from the PR, not the status.

_Jira_ (legacy, `OSR-<n>`):

The "Team." field (`customfield_23690`) carries the team; search results do not
return it, so query each team separately. Search results also omit `parent` and
the PR link field, which is why branches are joined by key. Use
`mcp__jira__jira_search_jql` with fields `summary, status, assignee, updated`.
`<inflight>` is
`status in (Developing, "Ready for Review", "Ready for Test", "Ready for Release")`.

1. In flight, per team (top-level items only; the open-everything query drowns
   in placeholder "Code review"/"Test" sub-tasks and years-old leftovers):
   `project = OSR AND "Team." = <Awesome|Brilliant> AND issuetype not in subTaskIssueTypes() AND <inflight>`
2. Ready queue size, per team (`max_results` 1, read `total_count`):
   `project = OSR AND "Team." = <team> AND issuetype not in subTaskIssueTypes() AND status = "Ready for development"`
3. Moved in the window, both teams. Use `CHANGED DURING`;
   `CHANGED AFTER "<date>"` silently returns nothing through this connector:
   `project = OSR AND "Team." in (Awesome, Brilliant) AND status CHANGED DURING ("<since yyyy-MM-dd>", now())`
4. Stuck:
   `project = OSR AND "Team." in (Awesome, Brilliant) AND issuetype not in subTaskIssueTypes() AND <inflight> AND NOT status CHANGED AFTER -7d`
5. Sub-tasks being worked under the query 1 keys (who is reviewing or testing
   what, and WIP per person):
   `project = OSR AND parent in (<keys>) AND status in ("In Progress", Verification)`

Page when `total_count` exceeds what came back.

In either tracker, an in-flight item last updated more than 180 days ago is a
zombie: count it under hygiene, never in the team section.

## 2) Join

- Ticket <-> branch/PR by the `keys` the collector extracted from branch names
  and PR titles (branches are cut from the top-level item, so keys are parent
  keys).
- Team of a branch/PR: from its key. With no key, use the author: anyone
  assigned to that team's issues in query 1 or 2 belongs to it.
- `agents/*` branches and PRs by **OSRAgent** are agent work. Keep them in their
  own short list; the human reviewer is the one to name.
- Keys that match neither team are other teams' work. Drop them silently.

## 3) Signals

Apply these; skip any section with nothing in it. Thresholds are starting
points; the user tunes them.

**Full validation** (PR Validation / DB Migrations). These are started by hand,
usually near the end of a work item, so "never run" is normal early. Rate each
PR:

| State       | Rule                                                          | Say                              |
| ----------- | ------------------------------------------------------------- | -------------------------------- |
| Not yet     | no run, ticket Developing                                     | nothing                          |
| Due         | no run, ticket Ready for Review or later                      | "never validated, in review"     |
| Stale green | last `S`, `commitsSince` > 0                                  | "green N commits ago"            |
| Red, idle   | last `F`/`C`, `pushesSince` = 0, run older than 1 working day | "red since <day>, no push since" |
| Red, fixing | last `F`/`C`, `pushesSince` > 0                               | "red, N pushes since, rerun?"    |
| Flaky?      | 2+ flips in `history` (`SFS`, `FSF`)                          | "flips between runs"             |
| Current     | last `S`, `commitsSince` = 0                                  | "validated on head" (good news)  |

Quote `failureMessages` in one line when red. A canceled chain is not a code
failure; say so.

**Review flow**

- No reviewers on a non-draft PR.
- Waiting on reviewers: all votes 0, PR older than 2 working days. Name them.
- Waiting on author: a `-5`/`-10` vote, or `lastCommentAt` after `lastPushAt`
  with active threads.
- Ready to merge: an approval (`10`/`5`), validation current, 0 active threads,
  `mergeStatus` succeeded. Nudge the author.
- Unresolved bot threads (CodeRabbit) only when > 3.
- `mergeStatus` = conflicts.

**Branch health**

- `ahead` = 0: merged or empty leftover. Count them under hygiene ("N merged
  branches not deleted"), never in the team section.
- Branch CI latest red (`ci[].result` failed) with `commitsSince` 0: broken
  head.
- `behind` > 20 merges or `baseDate` older than 10 days: "merge develop". Use
  `lastDevelopMerge` to say when they last did.
- `conflictCount` > 0: name up to 3 files.
- `migrationCount` > 0 on a PR near release: DB and app release order is chosen
  per release. Mention it, never as a blocker; never flag F-prefixed migrations.

**Tracker hygiene**

- Developing with no branch (not started?), Ready for Review with no PR.
- Branch/PR with no key (except `agents/*`, `dev/*`).
- Ticket Closed / Ready for Release while its branch still has unmerged commits.
- In-flight and unassigned; one person holding more than 2 in-flight items or
  sub-tasks (query 1 + query 5).
- Stuck (query 4), and zombies.

**Pipelines and release**

- develop: any latest non-`S`, or a failure in the last 3 runs. Nightly Test
  Bench failures matter to both teams.
- Prod: components with `newerGreenBuild`, sorted by `pendingMergeCount`; `db`
  with `pendingMigrations`. One line each.
- QA: which feature branch is on which env, with its ticket status. A branch on
  QA whose ticket is Closed means the env is free to reclaim.
- Merged in the window: one line per PR, grouped by team.

## 4) Output

Chat, markdown, no preamble. The two teams have separate standups, so each team
gets its own section, complete on its own; with a team argument, output only
that team's section plus Shared.

Formatting rules (the reader skims; flat prose does not work):

- Bullets everywhere, no paragraphs and no tables.
- One fact per bullet, about 12 words at most. Details go in sub-bullets.
- Start each item with a bold lead: the person, or the work item's short name.
- Lists of at most 5; put the rest in a count ("+4 more").
- **Never a bare number.** A key or PR number means nothing to the reader. Every
  mention of a work item, PR or branch leads with what it is, and the links
  follow in parentheses:
  `idle ETL agent monitor ([RPT-12](url), [PR 6842](url))`.
  - Short name: 2 to 5 words from the ticket summary, or the PR title when there
    is no ticket. Keep it recognizable, drop filler and series markers:
    "AngularJS retirement: user and org context [3 / 7]" becomes "AngularJS user
    context (3/7)"; "Feature flag aware content-availability layer for new
    sharing system" becomes "new sharing content layer".
  - Use the same short name for an item every time it appears in the output.
  - This applies in lists of keys too: "Closed: blob retry logging
    ([OSR-19561](url)), SDOP script for models ([OSR-19575](url))".
  - Links: RPT keys `https://linear.app/scarlet/issue/<key>`, OSR keys
    `https://jira.visma.com/browse/<key>`, PRs the PR `url`.
- An item belongs to the team of its ticket. An item with no team (develop red,
  a shared pipeline) goes under Shared, and also into both "Raise in the daily"
  lists when it blocks work.

Template:

```
**First thing:** <the single action to take before the dailies>

## Awesome

**Raise in the daily**
1. **Pontus: sharing migration tool conflicts with develop** ([OSR-19280](url), [PR 6778](url))
   - Why now: tags consolidation ([PR 6799](url)) merged Friday
   - Ask: merge develop before more review
2. ...

**In flight**
- **Idle ETL agent monitor** ([RPT-12](url)): Pontus, In Review
  - PR ([6842](url)): waiting on Pontus, 14 open threads
  - Validation: never run, due now
  - Branch: behind 3 PRs, deployed on QA2
- ...

**Moved since Fri**
- Done: blob retry logging ([RPT-7](url)), SDOP script for models ([OSR-19575](url))
- To review: idle ETL agent monitor ([RPT-12](url))

## Brilliant

(same three blocks)

## Shared

**Pipelines and release**
- develop: green (or what is red, with link)
- Prod behind develop:
  - **Zuora**: live since 30 Jun, 116 merges behind
- QA envs:
  - **qa1**: portal + db on new sharing + migration tool (Pontus, [OSR-18742](url))

**Agent work**
- **Borja**: 4 OSRAgent PRs waiting for review

**Hygiene (later)**
- 9 merged branches not deleted
- ...

Data: since Fri 25 Sep, collected 08:12.
```

In-flight sub-bullets are only the ones with something to say; a healthy item is
one line. If the collector or a query failed, say which part is missing instead
of guessing it.
