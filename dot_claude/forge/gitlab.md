# Running the skills against GitLab with `glab`

Every skill under `~/.claude/skills/` is written against the GitHub CLI (`gh`). When
`~/.claude/scripts/forge-detect.sh` prints `gitlab`, the workflow of the skill does not
change; only the commands do. This file maps every `gh` invocation the skills use to the
`glab` command that produces the same information or effect. Read it once per invocation,
then apply it to each `gh` command as you reach it. Do not read it on GitHub.

Verified against `glab 1.114`. Flags below come from `glab <command> --help`; JSON field
names are the GitLab REST API names, which `--output json` prints unchanged.

## Reading rules

- **Words.** Pull Request → Merge Request (MR). `#N` is an Issue iid, `!N` an MR iid.
  `Closes #N` in an MR description closes the Issue on merge, exactly as on GitHub.
  Checks / GitHub Actions → pipeline and jobs. Review decision → approvals plus
  discussion threads. Branch protection → protected branches and merge-request settings.
- **JSON.** Read commands take `--output json` and `--jq '<expr>'` (gojq; jq syntax).
  Always write the long flag `--output json`: on `glab issue list` the short `-F` means
  `--output-format`, not `--output`. Field names are the API names in the sections below.
- **Paging.** `gh --limit N` → `--per-page N` (max 100; add `--page 2`, `--page 3` when a
  page comes back full and the skill asked for more).
- **`glab api`.** Allowed for reads only, and only written as
  `glab api -X GET <endpoint>` (that exact prefix is what the permission allow-list
  matches). Never `-X POST|PUT|DELETE`, `--field`, `--raw-field`, `--input`, or `--form`:
  every skill that bans `gh api` writes bans `glab api` writes the same way. `:id` in an
  endpoint is replaced with the current project; `--paginate` fetches every page.
- **Repository flag.** `-R owner/repo` → `-R group/subgroup/project`; the value is the
  `<path>` forge-detect printed. Every `glab` command accepts `-R`.
- **Non-interactive.** Pass `--yes` to `mr create`, `mr merge`, `issue create`. Never
  pass `--description -` or omit both `--title` and `--description` (opens an editor).
  Multi-line text goes in as `--description "$(cat <file>)"` or `-m "$(cat <file>)"`.
- **URLs.** `https://<host>/<path>/-/issues/<N>`, `.../-/merge_requests/<iid>`,
  `.../-/pipelines/<id>`, `.../-/jobs/<id>`, `.../-/compare/<from>...<to>`,
  `.../-/releases/<tag>`.
- **Files in the repository.** `.github/PULL_REQUEST_TEMPLATE.md` →
  `.gitlab/merge_request_templates/*.md`; `.github/ISSUE_TEMPLATE/*.md` →
  `.gitlab/issue_templates/*.md`; `.github/workflows/*.yml` → `.gitlab-ci.yml`.

## Preflight

forge-detect already ran `glab auth status --hostname <host>`; the skill needs no second
check. Self-hosted instances are configured once with `glab auth login --hostname <host>`
(add `--api-host <host>:<port>` when the API is not on the default port). `GITLAB_HOST` is
not used: glab picks the host from the `origin` remote.

## Repository

### gh repo view

`glab repo view --output json` (add `-R <path>` when the skill passed one).

| gh `--json` field | glab JSON |
|---|---|
| `nameWithOwner` | `.path_with_namespace` (also what forge-detect printed) |
| `defaultBranchRef.name` | `.default_branch` |
| `visibility` / `isPrivate` | `.visibility` (`public`, `internal`, `private`) |
| `hasIssuesEnabled` | `.issues_enabled` (`.issues_access_level` when present) |
| `squashMergeAllowed` | `.squash_option != "never"` (`always` = squash is forced) |
| `mergeCommitAllowed` | `.merge_method == "merge"` |
| `rebaseMergeAllowed` | `.merge_method` is `rebase_merge` or `ff` |
| `deleteBranchOnMerge` | `.remove_source_branch_after_merge` |
| (branch protection) | `glab api -X GET projects/:id/protected_branches`; merge gates: `.only_allow_merge_if_pipeline_succeeds`, `.only_allow_merge_if_all_discussions_are_resolved` |
| (Actions enabled) | `.jobs_enabled` / `.builds_access_level` |

## Merge Requests (Pull Requests)

### gh pr view

- Current branch: `glab mr view --output json` (defaults to the checked-out branch);
  `gh pr view --json number` → `--jq .iid`.
- By number: `glab mr view <iid> --output json`.
- `--comments`: `glab mr view <iid> --comments` (text), or the discussions endpoint under
  [`gh api`](#gh-api) when you need author, position, and resolved state.

| gh `--json` field | glab JSON |
|---|---|
| `number` | `.iid` |
| `title`, `body`, `url` | `.title`, `.description`, `.web_url` |
| `state` (`OPEN`/`MERGED`/`CLOSED`) | `.state` (`opened`/`merged`/`closed`/`locked`) |
| `isDraft` | `.draft` |
| `headRefName`, `baseRefName`, `headRefOid` | `.source_branch`, `.target_branch`, `.sha` |
| `isCrossRepository` | `.source_project_id != .target_project_id` |
| `mergeable` | `.has_conflicts` (`true` → `CONFLICTING`) |
| `mergeStateStatus` | `.detailed_merge_status`: `mergeable`→`CLEAN`; `conflict`→`DIRTY`; `ci_must_pass`, `ci_still_running`→`UNSTABLE` (checks pending/failed); `blocked_status`, `discussions_not_resolved`, `not_approved`, `requested_changes`, `need_rebase`, `draft_status`, `external_status_checks`, `status_checks_must_pass`, `policies_denied`→`BLOCKED`; `unchecked`, `checking`, `preparing`→`UNKNOWN` (re-read after a moment) |
| `reviewDecision` | `.detailed_merge_status == "requested_changes"`→`CHANGES_REQUESTED`; `not_approved`→`REVIEW_REQUIRED`; approvals `.approved == true`→`APPROVED` (approvals: `glab api -X GET projects/:id/merge_requests/<iid>/approvals` → `.approved`, `.approvals_required`, `.approvals_left`, `.approved_by[].user.username`); otherwise `NONE` |
| `reviews` | approvals endpoint above + discussions (see [`gh api`](#gh-api)) |
| `labels` | `.labels` (array of names) |
| `mergedAt`, `mergeCommit` | `.merged_at`, `.merge_commit_sha` (`.squash_commit_sha` when squashed) |
| `commits` | `glab api -X GET projects/:id/merge_requests/<iid>/commits` → `.[].title` (headline), `.[].message`, `.[].id` |
| `files` | `glab api -X GET projects/:id/merge_requests/<iid>/diffs --paginate` → `.[].new_path`, `.old_path`, `.new_file`, `.deleted_file`, `.renamed_file` |
| `closingIssuesReferences` | `glab api -X GET projects/:id/merge_requests/<iid>/closes_issues` → `.[].iid` (also `glab mr issues <iid>`, text) |
| `statusCheckRollup` | see [`gh pr checks`](#gh-pr-checks) (`.head_pipeline.status` on the MR object is the one-line summary; `null` = no pipeline) |
| `updatedAt` | `.updated_at` |

### gh pr list

`glab mr list --output json --per-page 100` plus filters. Default is open MRs.

| gh | glab |
|---|---|
| `--state open` | (default) |
| `--state merged` | `--merged` |
| `--state closed` | `--closed` |
| `--state all` | `--all` |
| `--head <branch>` | `--source-branch <branch>` (add `--all` unless you want open only) |
| `--base <branch>` | `--target-branch <branch>` |
| `--label <name>` | `--label <name>` (comma-separated for several) |
| `--search "<text>"` | `--search "<text>"` |
| `--limit N` | `--per-page N` (max 100; page for more) |
| `--json number,state,isDraft,headRefName,body,url,updatedAt` | `--jq '.[] \| {iid, state, draft, source_branch, description, web_url, updated_at}'` |
| `--json closingIssuesReferences` | not in the list payload: derive from `.description` (`Closes|Fixes|Resolves #N`, case-insensitive), or per MR via `/closes_issues` under [`gh pr view`](#gh-pr-view) |

### gh pr diff

`glab mr diff <iid> --raw --color=never`. `--name-only` →
`glab api -X GET projects/:id/merge_requests/<iid>/diffs --paginate --output ndjson | jq -r .new_path`
(`glab api` has no `--jq`; without a `jq` binary, read the JSON directly).

### gh pr checks

`glab ci get --merge-request <iid> --output json --with-job-details`.

- Pipeline: `.status`, `.id`, `.web_url`, `.sha`. No pipeline for the MR (command errors
  or `head_pipeline` is `null` on the MR) → treat as "No checks reported".
- Jobs: `.jobs[]` with `.name`, `.stage`, `.status`, `.allow_failure`, `.id`, `.web_url`,
  `.started_at`, `.finished_at`. gh `bucket` mapping: `success`→pass; `failed`→fail
  (`allow_failure: true`→skipping); `running`, `pending`, `created`,
  `waiting_for_resource`, `preparing`, `scheduled`→pending; `canceled`, `skipped`,
  `manual`→skipping. gh `workflow` → `.stage`; `link` → `.web_url`.
- Do not use the exit code the way `gh pr checks` defines it; read `.status`.
- `--watch`: `glab ci status --branch <source_branch> --wait` (returns when the pipeline
  ends), then re-run `glab ci get` to read the result. Never `--live`.
- Job log: see [`gh run view`](#gh-run-view).

### gh pr create

```
glab mr create --title "<title>" --description "$(cat <body-file>)" \
  --source-branch <branch> --target-branch <base> [--label <a,b>] [--draft] --yes
```

The branch must already be pushed (do not use `--fill` or `--push`). `Closes #N` in the
description links and closes the Issue. Prints the MR URL.

### gh pr edit

`glab mr update <iid> [--title "<t>"] [--description "$(cat <file>)"] [--label <a,b>] [--unlabel <c>]`.
One MR per call, like `gh pr edit`.

### gh pr merge

```
glab mr merge <iid> --squash --remove-source-branch --auto-merge=false \
  --squash-message "$(printf '%s\n\n%s' "<subject>" "<body>")" --sha <headRefOid> --yes
```

- `--squash` only when `squash_option != "never"`; when the project's `merge_method` is
  `merge` and you are not squashing, put the message in `-m` instead of `--squash-message`.
- `--sha <sha>` refuses to merge if the source branch moved after you read it.
- `--auto-merge=false` merges now; the default (`true`) would only *schedule* the merge
  when a pipeline is still running, which the skills treat as "not merged".
- Afterwards `glab mr view <iid> --output json --jq .state` is `merged`.

### gh pr checkout

`glab mr checkout <iid>`.

### gh pr comment

`glab mr note create <iid> -m "$(cat <file>)" --resolvable=false`. `--resolvable=false`
keeps a status comment from becoming a thread that blocks merging on projects that require
all threads resolved. (`glab mr note` subcommands are marked experimental in 1.114; if
`create` is missing, `glab mr note <iid> -m "..."` is the older form.)

### gh pr review

`--comment --body-file <f>` → `glab mr note create <iid> -m "$(cat <f>)"` (a resolvable
thread — that is what a review is on GitLab). Never `--approve`/`glab mr approve` unless
the skill explicitly posts an approval; the skills do not.

## Issues

### gh issue view

`glab issue view <N> --output json`.

| gh `--json` field | glab JSON |
|---|---|
| `number`, `title`, `body`, `url` | `.iid`, `.title`, `.description`, `.web_url` |
| `state` (`OPEN`/`CLOSED`) | `.state` (`opened`/`closed`) |
| `stateReason` | none. Read the closing note (`--comments`) or `.closed_by`, or leave unknown |
| `labels` | `.labels` (array of names) |
| `updatedAt`, `closedAt`, `author` | `.updated_at`, `.closed_at`, `.author.username` |
| `comments` / `--comments` | `glab issue view <N> --comments` (text), or `glab api -X GET projects/:id/issues/<N>/notes --paginate` (`.[] \| select(.system == false)` → `.body`, `.author.username`, `.created_at`) |

### gh issue list

`glab issue list --output json --per-page N` plus filters. Default is open Issues.

| gh | glab |
|---|---|
| `--state open` / `--state all` / `--state closed` | (default) / `--all` / `--closed` |
| `--label a --label b` | `--label a,b` |
| `--milestone <title>` | `--milestone <title>` |
| `--search "<keywords>"` | `--search "<keywords>"` (title and description) |
| `--search "updated:>=<date>"` | `glab api -X GET "projects/:id/issues?state=opened&updated_after=<ISO-8601>&per_page=100" --paginate` (or `--order updated_at --sort desc` and stop reading at the date) |
| `--limit N` | `--per-page N` |
| `--json number,title,body,labels,state,url,updatedAt,author` | `--jq '.[] \| {iid, title, description, labels, state, web_url, updated_at, author: .author.username}'` |

### gh issue create

`glab issue create --title "<title>" --description "$(cat <file>)" [--label <a,b>] --yes`.
Prints the Issue URL.

### gh issue edit

`glab issue update <N> [--title "<t>"] [--description "$(cat <file>)"] [--label <a,b>] [--unlabel <c,d>]`.
One Issue per call (`gh issue edit` accepts several numbers; loop instead).

### gh issue close

No `--reason`. Two calls, in this order:

```
glab issue note <N> -m "$(printf '%s\n\n%s' "Closing as <completed | not planned>." "<text>")"
glab issue close <N>
```

State the reason on the first line of the note, since GitLab does not record one.

### gh issue comment

`glab issue note <N> -m "$(cat <file>)"`.

### gh issue pin

No equivalent; the skills only ban it. Nothing to run.

## Labels

### gh label list

`glab label list --output json --per-page 100` (page when full). Fields: `.id`, `.name`,
`.color` (with `#`), `.description`, `.is_project_label` (`false` = inherited group label,
which `glab label edit`/`delete` on the project cannot change).

`~/.claude/scripts/label-sync.sh` handles create/edit/rename/delete on GitLab itself; do
not run `glab label` by hand from the skills that use it.

## Releases

### gh release list

`glab release list --output json --per-page 20`. Fields: `.tag_name`, `.name`,
`.released_at`, `.created_at`, `.upcoming_release` (≈ prerelease), `.description`. There is
no draft state; the newest entry is the latest.

### gh release view

`glab release view <tag> --output json` (non-zero exit when the tag has no release);
`publishedAt` → `.released_at`. Without a tag it shows the latest release.

### gh release create

```
glab release create <tag> --ref <base> --name "<title>" --notes-file <file> --no-update
```

Creates the tag on `<base>` when it does not exist. `--no-update` makes it fail instead of
silently updating an existing release.

## CI

### gh workflow list

No equivalent. CI exists when `.gitlab-ci.yml` is at the repository root (or the project's
`ci_config_path` points elsewhere) and `glab ci list --per-page 1 --output json` returns a
pipeline. Actions disabled ↔ `.jobs_enabled == false` on the project.

### gh run list

`glab ci list --ref <branch> [--status failed] --per-page <N> --output json`. Fields:
`.id`, `.status`, `.ref`, `.sha`, `.source` (`push`, `merge_request_event`, ...),
`.web_url`, `.updated_at`. `--workflow <name>` has no equivalent (one pipeline per ref).
Pipeline id from a check link: the number after `/-/pipelines/`; a job link has
`/-/jobs/<job-id>`.

### gh run view

- `--json name,headSha,event,conclusion,jobs,url` → `glab ci get -p <pipeline-id> --output json --with-job-details`
  (`.status`, `.sha`, `.source`, `.web_url`, `.jobs[]` as under [`gh pr checks`](#gh-pr-checks)).
- `--log-failed` → for every `.jobs[] | select(.status == "failed")`: `glab ci trace <job-id> -p <pipeline-id>`
  (prints the whole log of a finished job and exits) or `glab api -X GET projects/:id/jobs/<job-id>/trace`.
- Annotations / "The job was not started" → `glab api -X GET "projects/:id/pipelines/<pipeline-id>/jobs?scope[]=failed"`
  → `.[] | {name, failure_reason}`; `failure_reason` is `script_failure` (the job's own
  commands), `runner_system_failure`, `stuck_or_timeout_failure`, `api_failure`,
  `scheduler_failure`, `data_integrity_failure`, `job_execution_timeout`, ... . Everything
  but `script_failure` is infrastructure. A pipeline stuck in `pending` with
  `stuck` warnings means no runner is available (the GitLab counterpart of Actions minutes
  or billing being exhausted).
- Attempts: retried jobs are new job ids in the same pipeline;
  `glab api -X GET "projects/:id/pipelines/<id>/jobs?include_retried=true"` shows them.

### gh run rerun

Banned in the skills; `glab ci retry` and `glab ci run` are banned the same way.

### gh run cancel

Banned; `glab ci cancel` is banned the same way.

### gh workflow run

Banned; `glab ci run` is banned the same way.

## Search

### gh search issues

`glab issue list -R <path> --search "<keywords>" [--all]` (title and description; open only
without `--all`). PR search → `glab mr list --search "<keywords>" [--all]`.

## API

### gh api

Only the read endpoints below, always as `glab api -X GET`:

| gh | glab |
|---|---|
| `repos/{o/r}/pulls/<N>/comments --paginate` (review comments with file/line) | `glab api -X GET projects/:id/merge_requests/<iid>/discussions --paginate` → each discussion `.id`, `.notes[]` with `.body`, `.author.username`, `.system` (skip `true`), `.resolvable`, `.resolved`, `.position.new_path`, `.position.new_line`, `.position.old_line`, `.created_at`. Alternative: `glab mr note list <iid> --type diff --output json` (experimental) |
| MR ↔ Issue links | `projects/:id/merge_requests/<iid>/closes_issues` |
| approvals | `projects/:id/merge_requests/<iid>/approvals` |
| commits / files of an MR | `projects/:id/merge_requests/<iid>/commits`, `.../diffs` |
| protected branches | `projects/:id/protected_branches` |
| `.gitignore` templates | `templates/gitignores/<name>` |

Anything a skill wants to *write* through `gh api` (resolving threads, replying inline,
label edits, branch protection) stays forbidden on GitLab.

## ci-review on GitLab

`ci-review` is written around GitHub Actions (checks → workflow runs → jobs → annotations).
On GitLab the objects are pipeline → jobs; the classification (pr-caused / pre-existing /
flaky / infrastructure / ci-definition) and every stop rule stay the same. Substitutions:

1. Checks of the MR: `glab ci get --merge-request <iid> --output json --with-job-details`
   (see [`gh pr checks`](#gh-pr-checks)); failing checks are `.jobs[]` with `.status ==
   "failed"` and `.allow_failure == false`. `--workflow <name>` filters `.jobs[].name` or
   `.stage`.
2. Failure logs: `glab ci trace <job-id> -p <pipeline-id>` per failed job.
3. Failure reasons: `.../pipelines/<id>/jobs?scope[]=failed` → `failure_reason`
   (`script_failure` = the job's own commands; anything else = infrastructure).
4. Base-branch history: `glab ci list --ref <base> --per-page 5 --output json`, then
   `glab ci get -p <id> --output json --with-job-details` per pipeline to compare job
   names and statuses. Head-branch history: `glab ci list --ref <source_branch> --per-page 10 --output json`.
5. CI definition: `.gitlab-ci.yml` (and files it `include:`s) instead of
   `.github/workflows/*.yml`; `glab ci lint` is a read-only validator you may run.
6. Actions minutes / billing → no runner picked the job up (`pending` with a `stuck`
   warning, or `failure_reason: runner_system_failure`); still infrastructure.

## Not available on GitLab

| gh feature | what to do |
|---|---|
| `gh issue close --reason` | note first, then close (see [`gh issue close`](#gh-issue-close)) |
| `stateReason` on Issues | leave unknown; do not infer "not planned" |
| `isLatest`/`isDraft` on releases | newest entry is latest; drafts do not exist |
| `gh pr checks --watch` exit codes | `glab ci status --wait`, then re-read `.status` |
| review threads: resolve, inline reply | still forbidden (write API) |
| `gh workflow list` | `.gitlab-ci.yml` + `glab ci list --per-page 1` |
| `--workflow <name>` on run list | filter jobs by `.stage`/`.name` instead |
| `gh label edit` from a skill | only through `label-sync.sh` |
| `updated:>=` search qualifier | `updated_after=` on the Issues API |
