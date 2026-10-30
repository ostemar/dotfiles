# Dependabot: shared reference

Read by `/dependabot-status`, `/dependabot-merge` and `/dependabot-fix`. This
repo is public: nothing here names a private repo. The repos are found at run
time.

## Which repos

Every non-archived, non-fork repo of the signed-in user that has Dependabot
alerts turned on:

```bash
OWNER=$(gh api user -q .login)
gh repo list "${OWNER}" -L 200 --no-archived --source --json name -q '.[].name' |
  while read -r r; do
    code=$(gh api -i "repos/${OWNER}/${r}/vulnerability-alerts" 2>/dev/null | head -1 | awk '{print $2}')
    echo "${r} ${code}"   # 204 on, 404 off, anything else an error to report
  done
```

Keep the 204s. List the 404s on one line as "alerts off"; report any other
status as an error, not as off. If the user names repos, use only those.

Scratch files go in the session's scratchpad directory, never `/tmp`.

## Queries

```bash
# Open alerts, one line each
gh api "repos/${OWNER}/${r}/dependabot/alerts?state=open&per_page=100" --paginate \
  -q '.[]|[.number,.security_advisory.severity,.dependency.package.name,.dependency.scope,.security_vulnerability.vulnerable_version_range,(.security_vulnerability.first_patched_version.identifier//"none"),.security_advisory.withdrawn_at]|@tsv'

# Open Dependabot PRs, with checks and mergeability
gh pr list -R "${OWNER}/${r}" --author app/dependabot \
  --json number,title,createdAt,headRefName,mergeStateStatus,statusCheckRollup,labels
```

**Which alerts a PR covers.** Do not go by the PR body: its wording varies and
a grouped PR's body does not list every package. Nor by grepping the diff: in
`package-lock.json` the name and the version sit on different lines. A PR
covers an alert when, *installed*, it resolves that package to at least the
first patched version: on the PR head after the install, `npm ls <pkg> --all`,
`pnpm why <pkg>`, `cargo tree -i <pkg>` or `go list -m <mod>`. That needs a
clone, so `/dependabot-status` reports coverage as unchecked and
`/dependabot-merge` and `/dependabot-fix` establish it. A PR that covers an
open alert is a **security** PR; any other is a version PR.

**Kinds of bump.** A title with "group" is grouped minor/patch updates. A
**breaking** bump is a semver major *or* a `0.x` to `0.y` (semver calls the
latter minor, but in 0.x it breaks). Say "breaking", not "major", so the two
are not confused.

**Checks have three states, not two:** passing, failing, and **none** (no
check ran at all). A PR with no checks has no evidence, and is treated like a
repo whose checks only build: the gate runs locally.

## The gate: what proves a change works

In order of preference:

1. The repo's own `CLAUDE.md` or `AGENTS.md`, if it names a gate or the
   commands to run before a commit. Follow it exactly.
2. Otherwise derive it from the manifest:
   - pnpm/npm: `install --frozen-lockfile` (`npm ci`), then whichever exist of
     `typecheck`/`type-check`, `test` (run it non-interactively: `vitest run`,
     `CI=1`), `lint`, `build`.
   - Cargo: `cargo fmt --check && cargo clippy --all-targets && cargo test`.
   - Go: `go vet ./... && go test ./...`.

A repo with no tests, typecheck or lint (a static site) has the build as its
whole gate. Then also compare what the build produced with main's (page or
file count, new warnings), and call the result "verified, build only": it
counts as verified, but say so in the table.

**Always run the gate on `main` first.** A failure that is already on main is a
baseline, not a regression; report it, never fix it as part of a dependency
change.

Where to work: the user keeps every repo in `~/code/<repo>`.

- Work that ends in a commit (a fix, a formatting pass): if `~/code/<repo>`
  does not exist, clone it there and work in it. If it exists and sits on
  `main` with a clean tree, pull and work there. If it has other work in
  progress (another branch, uncommitted changes), leave it untouched and use
  a clone in the session's scratchpad.
- Verifying PRs without committing (merge step 2, unattended runs): a clone
  in the session's scratchpad, so nothing in `~/code` changes.

## What the PR checks prove

Look at what a repo's checks actually run before trusting a green tick. A
Cloudflare Workers or Pages build only builds: green there means it compiles,
not that the tests pass. A repo with no workflow that runs tests has no test
signal on its PRs at all, and its PRs need the gate run locally.

## Rules

- **Never force-push**, and never to a Dependabot branch. If a Dependabot PR
  is out of date and `@dependabot rebase` has not acted within ten minutes,
  merge `main` into its branch (regenerating the lockfile if it conflicts) and
  push that.
- **Merging is the user's decision.** Ask once, for the whole list, with one
  question. An unattended (scheduled) run never merges; it reports what it
  would merge.
- Squash-merge, which is how these repos land PRs, and pass `--delete-branch`.
- Commits and PR bodies: a short subject line, at most a few bullets. No
  Claude or AI attribution anywhere. Only the ASCII hyphen `-`: no em dash, en
  dash or minus sign.
- No major bumps of direct dependencies inside an alert fix; those are their
  own PR, read on their own.

## Traps that have bitten before

- The Bash tool may evaluate in zsh: write `${VAR}` before a colon (`$B:r` is
  a zsh modifier) and quote jq filters containing `[...]`.
- A `pnpm.overrides` entry pinned to an exact version (`"5.0.10"`) freezes the
  lockfile on it, and the next advisory against that package cannot be fixed
  by an update. Write overrides as a floor: `"pkg@<X.Y.Z": "^X.Y.Z"`.
- `pnpm update` also raises the `^` floors in `package.json`; that is expected.
- Dependabot `groups` are not first-match: a dependency matching a named group
  and the `production`/`development` group can land in the latter.
- A `vite.config` that loads `vite-plugin-mkcert` makes `vitest` try to
  install a root CA with sudo, so the tests fail before running. Run them with
  a temporary config without that plugin, delete it afterwards, and say so.
- A PR made redundant by a bigger one (a framework major that pulls the same
  patched versions) is not always closed at once; Dependabot may wait for its
  next run. If `main`'s lockfile already has the PR's target version, say so
  and leave it, rather than merging a no-op.
- New alerts can appear right after a fix lands: the rescan finds advisories
  published since. Re-list before saying a repo is clear.

## Notifying the user

At the end of a run that found something the user must act on, send one push
notification if a notification tool is available (`PushNotification`): one
line, what needs them and where. Nothing to act on means no notification.
