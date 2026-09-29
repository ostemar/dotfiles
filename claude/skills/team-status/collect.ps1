<#
.SYNOPSIS
    Collects git and Azure DevOps facts for the team status as JSON.

.DESCRIPTION
    Read-only: fetches origin, then reads branches, pull requests, PR validation
    history, branch CI, develop/nightly pipeline health, recently merged PRs and
    release deployments. Never queues builds, pushes, or touches the working tree.
    Tracker data (Linear RPT-n, legacy Jira OSR-n) is not collected here; the
    team-status skill joins it in by the keys found in branch names and PR titles.

.EXAMPLE
    pwsh -NoProfile -File ~/.claude/skills/team-status/collect.ps1 -OutFile team-status.json
#>
param(
    [string]$OutFile,
    # OSR checkout to read. Defaults to the current repo when it is OSR, else C:\code\OSR.
    [string]$RepoPath,
    # Start of the "what happened lately" window. Defaults to the previous
    # working day at 00:00, so Monday looks back to Friday.
    [datetime]$Since,
    # Branches without an active PR are included when they have commits this recent.
    [int]$ActiveDays = 14,
    # PRs with no creation or branch commit this recent are skipped (some very
    # old PRs are stuck and cannot even be deleted); only their count is reported.
    [int]$PrMaxAgeDays = 90,
    [switch]$NoFetch
)

$ErrorActionPreference = 'Stop'

function Test-OsrRepo([string]$Path) {
    $origin = git -C $Path remote get-url origin 2>$null
    $LASTEXITCODE -eq 0 -and $origin -match 'dev\.azure\.com/onestopreporting/OSRSuite/_git/OSR$'
}
if (-not $RepoPath) {
    $current = git rev-parse --show-toplevel 2>$null
    $RepoPath = if ($current -and (Test-OsrRepo $current)) { $current } else { 'C:\code\OSR' }
}
if (-not (Test-Path $RepoPath) -or -not (Test-OsrRepo $RepoPath)) {
    throw "No OSR checkout at '$RepoPath'. Pass -RepoPath <path to the OSR repo>."
}
$repoRoot = (git -C $RepoPath rev-parse --show-toplevel).Trim()
Set-Location $repoRoot

$org = "https://dev.azure.com/onestopreporting"
$project = "OSRSuite"
$api = "$org/$project/_apis"
$releaseApi = "https://vsrm.dev.azure.com/onestopreporting/$project/_apis/release"
$repoWeb = "$org/$project/_git/OSR"

# Build definitions worth tracking. PR Validation and DB Migrations are the
# manual-queue PR policies (25 / 31); the rest are branch and nightly health.
$validationDefinitions = @(230, 229)
$developDefinitions = @(223, 229, 217, 222, 133, 118)
$branchCiDefinitions = @(223, 217, 229)
$releasePipelines = [ordered]@{
    portal = 39; gateway = 34; agent = 37; broker = 76; render = 40; etl = 43
    etlscheduler = 72; publisher = 46; publisherscheduler = 47; notification = 44
    maintenance = 45; cleanup = 63; zuora = 51; voucher = 52; pdfconverter = 82
    warehouse = 86; db = 55; designer = 83
}
$botAuthors = @('OSRAgent', 'CodeRabbit', 'Microsoft.VisualStudio.Services.TFS', 'Project Collection Build Service (onestopreporting)')

# Uppercase issue keys in a branch name or PR title: Linear RPT-<n> and legacy
# Jira OSR-<n>. "osr-123-456" names several OSR items; RPT gets no such form,
# as its short numbers are indistinguishable from a slug starting with a digit.
function Get-IssueKeys([string]$Text) {
    @(
        foreach ($m in [regex]::Matches($Text, '(?i)\brpt-(\d+)')) { "RPT-$($m.Groups[1].Value)" }
        foreach ($m in [regex]::Matches($Text, '(?i)osr-(\d{4,6})((?:-\d{4,6})*)')) {
            "OSR-$($m.Groups[1].Value)"
            $m.Groups[2].Value -split '-' | Where-Object { $_ } | ForEach-Object { "OSR-$_" }
        }
    ) | Select-Object -Unique
}
$getIssueKeys = ${function:Get-IssueKeys}.ToString()

if (-not $Since) {
    $Since = (Get-Date).Date.AddDays(-1)
    while ($Since.DayOfWeek -in 'Saturday', 'Sunday') { $Since = $Since.AddDays(-1) }
}
$sinceUtc = $Since.ToUniversalTime()

$token = az account get-access-token --resource 499b84ac-1321-427f-aa17-267ca6975798 --query accessToken -o tsv 2>$null
if ($LASTEXITCODE -ne 0 -or -not $token) { throw "Could not get an Azure DevOps token. Run 'az login' first." }
$headers = @{ Authorization = "Bearer $token" }

function Get-Ado([string]$Uri) {
    (Invoke-RestMethod -Headers $headers -Uri $Uri).value
}

if (-not $NoFetch) { git fetch --prune --quiet origin 2>$null }

$projectId = (Invoke-RestMethod -Headers $headers -Uri "$org/_apis/projects/$project`?api-version=7.1").id

# --- Pull requests -----------------------------------------------------------
$allActivePrs = @(Get-Ado "$api/git/repositories/OSR/pullrequests?searchCriteria.status=active&`$top=300&api-version=7.1")
$prCutoff = (Get-Date).AddDays(-$PrMaxAgeDays)
$activePrs = @($allActivePrs | Where-Object {
        if ([datetime]$_.creationDate -ge $prCutoff) { return $true }
        $lastCommit = git log -1 --format='%cI' ($_.sourceRefName -replace '^refs/heads/', 'origin/') 2>$null
        $lastCommit -and [datetime]$lastCommit -ge $prCutoff
    })
$mergedPrs = @(Get-Ado ("$api/git/repositories/OSR/pullrequests?searchCriteria.status=completed" +
        "&searchCriteria.targetRefName=refs/heads/develop&searchCriteria.queryTimeRangeType=closed" +
        "&searchCriteria.minTime=$($sinceUtc.ToString('o'))&`$top=200&api-version=7.1"))

$prDetails = $activePrs | ForEach-Object -ThrottleLimit 16 -Parallel {
    $pr = $_
    $h = $using:headers
    $base = "$using:api/git/repositories/OSR/pullrequests/$($pr.pullRequestId)"
    $errors = [System.Collections.Generic.List[string]]::new()
    # One failing endpoint (ADO sometimes 500s on threads) should not drop the PR.
    $get = {
        param($what, $uri)
        try { @((Invoke-RestMethod -Headers $h -Uri $uri).value) }
        catch { $errors.Add("${what}: $($_.Exception.Message)"); @() }
    }
    $iterations = & $get 'iterations' "$base/iterations?api-version=7.1"
    $threads = @(& $get 'threads' "$base/threads?api-version=7.1" |
            Where-Object { -not $_.isDeleted -and $_.comments[0].commentType -ne 'system' })
    $builds = & $get 'builds' ("$using:api/build/builds?branchName=refs/pull/$($pr.pullRequestId)/merge" +
        "&definitions=$($using:validationDefinitions -join ',')&queryOrder=queueTimeDescending&`$top=20&api-version=7.1")
    $policies = & $get 'policies' ("$using:api/policy/evaluations?artifactId=vstfs:///CodeReview/CodeReviewId/" +
        "$using:projectId/$($pr.pullRequestId)&api-version=7.1-preview.1")
    [pscustomobject]@{ Id = $pr.pullRequestId; Iterations = $iterations; Threads = $threads; Builds = $builds; Policies = $policies; Errors = @($errors) }
}
$prDetailById = @{}
foreach ($d in $prDetails) { $prDetailById[$d.Id] = $d }

# --- Branch selection ----------------------------------------------------------
$prBySource = @{}
foreach ($pr in $activePrs) { $prBySource[$pr.sourceRefName -replace '^refs/heads/', ''] = $pr }

$cutoff = (Get-Date).AddDays(-$ActiveDays).ToString('yyyy-MM-dd')
$recentBranches = git for-each-ref --format='%(committerdate:short) %(refname:lstrip=3)' refs/remotes/origin |
    ForEach-Object { $date, $name = $_ -split ' ', 2; if ($date -ge $cutoff) { $name } } |
    Where-Object { $_ -and $_ -notin 'HEAD', 'develop', 'master', 'main' -and $_ -notmatch '^release/' }
$branchNames = @(@($prBySource.Keys) + @($recentBranches) | Sort-Object -Unique |
        Where-Object { git rev-parse --verify --quiet "refs/remotes/origin/$_" })

# --- Per-branch git state and CI -------------------------------------------------
$branches = $branchNames | ForEach-Object -ThrottleLimit 12 -Parallel {
    $name = $_
    $ref = "origin/$name"
    Set-Location $using:repoRoot
    ${function:Get-IssueKeys} = $using:getIssueKeys
    $count = { param($range) [int](git rev-list --count @($range -split ' ') 2>$null) }

    $mergeBase = (git merge-base origin/develop $ref).Trim()
    $ahead = & $count "origin/develop..$ref"
    # Merges on develop since the branch point: roughly "PRs this branch has not seen".
    $behind = & $count "--first-parent $ref..origin/develop"
    $authors = @(git log --format='%an' "origin/develop..$ref" | Group-Object | Sort-Object Count -Descending)
    $lastCommit = git log -1 --format='%cI|%an|%s' $ref
    $lastDate, $lastAuthor, $lastSubject = $lastCommit -split '\|', 3
    $baseDate = git log -1 --format='%cI' $mergeBase
    # Most recent "develop into branch" merge: a merge on the branch's own history
    # whose second parent is already on develop.
    $lastDevelopMerge = $null
    foreach ($line in git log --merges --first-parent --format='%H %P %cI' "origin/develop..$ref") {
        $parts = $line -split ' '
        if ($parts.Count -ge 4) { git merge-base --is-ancestor $parts[2] origin/develop }
        if ($parts.Count -ge 4 -and $LASTEXITCODE -eq 0) {
            $lastDevelopMerge = $parts[-1]; break
        }
    }
    $conflicts = @()
    $mergeTree = git merge-tree --write-tree --name-only --no-messages origin/develop $ref 2>$null
    if ($LASTEXITCODE -eq 1) { $conflicts = @($mergeTree | Select-Object -Skip 1 | Where-Object { $_ }) }
    $migrations = @(git diff --name-only $mergeBase $ref -- Source/Migrations | Where-Object { $_ -match '\.sql$' })

    $builds = @((Invoke-RestMethod -Headers $using:headers -Uri ("$using:api/build/builds?branchName=refs/heads/$name" +
                "&queryOrder=queueTimeDescending&`$top=30&api-version=7.1")).value)
    # Keep the main CI pipelines, plus any other pipeline whose latest run is not
    # green. Path-filtered pipelines (Terraform, function apps...) otherwise show
    # hundreds of "commits since", which only means their paths did not change.
    $ci = foreach ($group in $builds | Group-Object { $_.definition.name }) {
        $runs = @($group.Group | Where-Object status -EQ 'completed')
        if (-not $runs) { continue }
        $latest = $runs[0]
        if ($latest.definition.id -notin $using:branchCiDefinitions -and $latest.result -eq 'succeeded') { continue }
        $built = $latest.sourceVersion
        git cat-file -e "$built^{commit}" 2>$null
        $builtKnown = $LASTEXITCODE -eq 0
        [pscustomobject]@{
            definition   = $group.Name
            result       = $latest.result
            finishedAt   = $latest.finishTime
            url          = if ($latest.result -ne 'succeeded') { "$using:org/$using:project/_build/results?buildId=$($latest.id)" }
            commitsSince = if ($builtKnown) { & $count "$built..$ref" } else { $null }
            history      = -join ($runs | Select-Object -First 5 | ForEach-Object { $_.result.Substring(0, 1).ToUpper() })
        }
    }

    [pscustomobject]@{
        name             = $name
        keys             = @(Get-IssueKeys $name)
        author           = if ($authors) { $authors[0].Name } else { $lastAuthor }
        lastCommitAt     = $lastDate
        lastCommitBy     = $lastAuthor
        lastCommit       = $lastSubject
        ahead            = $ahead
        behind           = $behind
        baseDate         = $baseDate
        lastDevelopMerge = $lastDevelopMerge
        conflictCount    = $conflicts.Count
        conflicts        = @($conflicts | Select-Object -First 5)
        migrationCount   = $migrations.Count
        migrations       = @($migrations | Select-Object -First 5 | ForEach-Object { Split-Path $_ -Leaf })
        ci               = @($ci)
    }
}
$branchByName = @{}
foreach ($b in $branches) { $branchByName[$b.name] = $b }

# --- PR summaries -------------------------------------------------------------------
$now = [datetime]::UtcNow
$prs = foreach ($pr in $activePrs) {
    $d = $prDetailById[$pr.pullRequestId]
    $source = $pr.sourceRefName -replace '^refs/heads/', ''
    $branch = $branchByName[$source]
    $iterations = @($d.Iterations | Sort-Object { [datetime]$_.createdDate })
    $head = "origin/$source"

    # Validation runs are on the PR merge commit, so map each run back to the
    # source commit of the newest push made before it was queued.
    $validation = foreach ($group in $d.Builds | Group-Object { $_.definition.name }) {
        $runs = @($group.Group)
        $done = @($runs | Where-Object status -EQ 'completed')
        $latest = $runs[0]
        $queued = [datetime]$latest.queueTime
        $pushedBefore = $iterations | Where-Object { [datetime]$_.createdDate -le $queued } | Select-Object -Last 1
        $validatedCommit = $pushedBefore.sourceRefCommit.commitId
        [pscustomobject]@{
            definition         = $group.Name
            status             = $latest.status
            result             = $latest.result
            queuedAt           = $latest.queueTime
            url                = "$org/$project/_build/results?buildId=$($latest.id)"
            runs               = $runs.Count
            history            = -join ($done | Select-Object -First 8 | ForEach-Object { $_.result.Substring(0, 1).ToUpper() })
            everGreen          = [bool]($done | Where-Object result -EQ 'succeeded')
            pushesSince        = @($iterations | Where-Object { [datetime]$_.createdDate -gt $queued }).Count
            commitsSince       = if ($validatedCommit) { [int](git rev-list --count "$validatedCommit..$head" 2>$null) } else { $null }
            failureMessages    = @(($d.Policies | Where-Object { $_.context.buildId -eq $latest.id }).context.buildOutputPreview.errors.message |
                    Where-Object { $_ -notmatch 'exited with code' } | Select-Object -First 3)
        }
    }

    $humanThreads = @($d.Threads | Where-Object { $_.comments[0].author.displayName -notin $botAuthors })
    $botThreads = @($d.Threads | Where-Object { $_.comments[0].author.displayName -in $botAuthors })
    $lastComment = $d.Threads | ForEach-Object { $_.comments } | Where-Object { $_.author.displayName -notin $botAuthors } |
        Sort-Object { [datetime]$_.lastUpdatedDate } | Select-Object -Last 1
    $lastPush = $iterations | Select-Object -Last 1
    $buildPolicy = $d.Policies | Where-Object { $_.configuration.type.displayName -eq 'Build' } |
        ForEach-Object { [pscustomobject]@{ name = $_.configuration.settings.displayName; status = $_.status; expired = [bool]$_.context.isExpired } }

    [pscustomobject]@{
        id               = $pr.pullRequestId
        url              = "$repoWeb/pullrequest/$($pr.pullRequestId)"
        title            = $pr.title
        author           = $pr.createdBy.displayName
        isDraft          = $pr.isDraft
        source           = $source
        keys             = @(@($branch.keys) + @(Get-IssueKeys $pr.title) | Select-Object -Unique)
        createdAt        = $pr.creationDate
        ageDays          = [int]($now - [datetime]$pr.creationDate).TotalDays
        mergeStatus      = $pr.mergeStatus
        autoComplete     = [bool]$pr.autoCompleteSetBy
        reviewers        = @($pr.reviewers | Where-Object { -not $_.isContainer } |
                ForEach-Object { [pscustomobject]@{ name = $_.displayName; vote = $_.vote; required = [bool]$_.isRequired } })
        pushes           = $iterations.Count
        lastPushAt       = $lastPush.createdDate
        activeThreads    = @($humanThreads | Where-Object status -EQ 'active').Count
        activeBotThreads = @($botThreads | Where-Object status -EQ 'active').Count
        lastCommentAt    = $lastComment.lastUpdatedDate
        lastCommentBy    = $lastComment.author.displayName
        buildPolicies    = @($buildPolicy)
        validation       = @($validation)
        collectErrors    = $d.Errors
    }
}

# --- develop and nightly health -----------------------------------------------------
$developBuilds = @(Get-Ado ("$api/build/builds?branchName=refs/heads/develop&definitions=$($developDefinitions -join ',')" +
        "&queryOrder=queueTimeDescending&`$top=120&api-version=7.1"))
$develop = foreach ($group in $developBuilds | Where-Object status -EQ 'completed' | Group-Object { $_.definition.id }) {
    $runs = @($group.Group)
    [pscustomobject]@{
        definition = $runs[0].definition.name
        result     = $runs[0].result
        finishedAt = $runs[0].finishTime
        url        = "$org/$project/_build/results?buildId=$($runs[0].id)"
        history    = -join ($runs | Select-Object -First 8 | ForEach-Object { $_.result.Substring(0, 1).ToUpper() })
    }
}

# --- Releases: what is live, and how far prod trails develop --------------------------
$definitions = @(Get-Ado "$releaseApi/definitions?`$expand=environments&api-version=7.1")
$targets = foreach ($name in $releasePipelines.Keys) {
    $definition = $definitions | Where-Object id -EQ $releasePipelines[$name]
    foreach ($stage in $definition.environments) {
        if ($stage.name -match 'staging|swap') { continue }
        $env = ($stage.name -replace '\s*\(Azure\)\s*$', '' -replace '\s', '').ToLower()
        if ($env -notmatch '^(prod|qa\d)$') { continue }
        [pscustomobject]@{ Name = $name; Env = $env; DefinitionId = $definition.id; EnvironmentId = $stage.id }
    }
}
$deployments = $targets | ForEach-Object -ThrottleLimit 16 -Parallel {
    $t = $_
    $uri = "$using:releaseApi/deployments?definitionId=$($t.DefinitionId)&definitionEnvironmentId=$($t.EnvironmentId)" +
        "&deploymentStatus=succeeded,partiallySucceeded&queryOrder=descending&`$top=1&api-version=7.1"
    $deployed = (Invoke-RestMethod -Headers $using:headers -Uri $uri).value | Select-Object -First 1
    if (-not $deployed) { return }
    $artifact = $deployed.release.artifacts | Sort-Object { -not $_.isPrimary } | Select-Object -First 1
    [pscustomobject]@{
        pipeline     = $t.Name
        env          = $t.Env
        branch       = $artifact.definitionReference.branch.name -replace '^refs/heads/', ''
        commit       = $artifact.definitionReference.sourceVersion.id
        ciDefinition = [int]$artifact.definitionReference.definition.id
        build        = $artifact.definitionReference.version.name
        deployedAt   = $deployed.completedOn
        by           = $deployed.requestedFor.displayName
    }
}

# Prod lag: deployed CI build vs the latest green develop build of the same CI
# definition, and the develop merges between the two commits.
$prodRows = @($deployments | Where-Object env -EQ 'prod')
$ciIds = @($prodRows.ciDefinition | Sort-Object -Unique)
$latestGreen = @{}
foreach ($b in Get-Ado ("$api/build/builds?branchName=refs/heads/develop&definitions=$($ciIds -join ',')" +
        "&resultFilter=succeeded&maxBuildsPerDefinition=1&api-version=7.1")) {
    $latestGreen[[int]$b.definition.id] = $b
}
$prod = foreach ($row in $prodRows) {
    $green = $latestGreen[$row.ciDefinition]
    $pending = @()
    if ($row.branch -eq 'develop' -and $green -and $row.commit -and $green.sourceVersion -ne $row.commit) {
        $pending = @(git log --first-parent --format='%s' "$($row.commit)..$($green.sourceVersion)" 2>$null |
                Where-Object { $_ -match '^Merged PR' })
    }
    [pscustomobject]@{
        pipeline          = $row.pipeline
        branch            = $row.branch
        build             = $row.build
        deployedAt        = $row.deployedAt
        by                = $row.by
        newerGreenBuild   = if ($green -and $green.sourceVersion -ne $row.commit) { $green.buildNumber } else { $null }
        pendingMergeCount = $pending.Count
        pendingMerges     = @($pending | Select-Object -First 10)
        pendingMigrations = if ($row.pipeline -eq 'db' -and $row.commit) {
            @(git diff --name-only $row.commit origin/develop -- Source/Migrations 2>$null | Where-Object { $_ -match '\.sql$' })
        } else { @() }
    }
}
# QA: feature branches currently deployed, plus anything deployed in the window.
$qa = @($deployments | Where-Object { $_.env -match '^qa' -and ($_.branch -ne 'develop' -or [datetime]$_.deployedAt -ge $sinceUtc) } |
        Sort-Object env, pipeline | Select-Object env, pipeline, branch, deployedAt, by)

$merged = foreach ($pr in $mergedPrs) {
    [pscustomobject]@{
        id       = $pr.pullRequestId
        title    = $pr.title
        author   = $pr.createdBy.displayName
        closedAt = $pr.closedDate
        keys     = @(Get-IssueKeys "$($pr.title) $($pr.sourceRefName)")
    }
}

$result = [ordered]@{
    generatedAt = (Get-Date).ToString('o')
    since       = $Since.ToString('o')
    skippedOldPrs = $allActivePrs.Count - $activePrs.Count
    develop     = [ordered]@{
        head      = (git log -1 --format='%h %s' origin/develop)
        pipelines = @($develop)
    }
    prs         = @($prs | Sort-Object id -Descending)
    branches    = @($branches | Sort-Object lastCommitAt -Descending)
    merged      = @($merged)
    prod        = @($prod)
    qa          = $qa
}

$json = $result | ConvertTo-Json -Depth 8 -Compress
if ($OutFile) { Set-Content -Path $OutFile -Value $json -Encoding utf8; Write-Host "Wrote $OutFile" }
else { $json }
