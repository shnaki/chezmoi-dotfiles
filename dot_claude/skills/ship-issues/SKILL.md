---
name: ship-issues
description: "Orchestrate implementation of multiple existing GitHub Issues by analyzing dependencies, planning safe parallel execution, and delegating each Issue to an isolated worker that creates exactly one Pull Request."
argument-hint: "[issue-numbers...] [--merge] [--ignore-checks] [--dry-run] [--resume] [--no-merge] [--worker-model <alias>]"
disable-model-invocation: true
---

Process the GitHub Issues specified in `$ARGUMENTS`.

This skill is an orchestrator.

Do not directly implement the Issues in the orchestrator context.

Each Issue must be implemented independently by a dedicated worker in an isolated branch/worktree.

# Goals

For the supplied Issues:

1. validate that each Issue is actionable
2. inspect likely implementation impact
3. identify dependencies and conflicts
4. determine which Issues can safely run in parallel
5. organize execution into waves
6. delegate exactly one Issue to each implementation worker
7. collect the resulting Pull Requests and verification status

The intended model is:

Issues
→ dependency analysis
→ execution waves
→ isolated Issue workers
→ one Pull Request per Issue

# Core rules

- One Issue corresponds to exactly one Pull Request.
- One implementation worker handles exactly one Issue.
- Never combine multiple Issues into one Pull Request.
- Never allow multiple workers to modify the same worktree.
- Independent Issues should run concurrently when safe.
- File non-overlap alone is not sufficient evidence of independence.
- Do not modify Issue requirements merely to make parallelization easier.
- Workers never merge. Merging happens only in the orchestrator, only with `--merge`, and only through the `pr-land` workflow.
- Keep detailed implementation work out of the orchestrator context.
- All forge operations (reading, searching, and creating Issues and Pull Requests) go
  through the forge CLI: `gh` on GitHub, `glab` on GitLab. Before the first such call, run
  `sh ~/.claude/scripts/forge-detect.sh`; it prints one line, `<forge> <host> <path>`. On
  `github`, run the `gh` commands below as written. On `gitlab`, read
  `~/.claude/forge/gitlab.md` once and run the `glab` equivalent it gives for each `gh`
  command below, following its degrade rules where it lists none. If the script fails,
  stop and report its message instead of falling back to another client. Workers get the
  same instruction through the worker prompt (step 7).

# 1. Parse the requested Issues

Interpret `$ARGUMENTS` as the set of Issue numbers to process, plus options.

Accept common forms such as:

- `101 102 103`
- `#101 #102 #103`
- `101,102,103`
- full Issue URLs on the repository's forge host (`https://<host>/<path>/issues/101`,
  `https://<host>/<path>/-/issues/101`)

Strip any leading `#` so a number is never interpolated as `##101`.

Normalize the input into a unique Issue list.

Do not process unrelated Issues that were not requested.

Then establish the repository facts every later step relies on:

- the base branch: `gh repo view --json defaultBranchRef --jq .defaultBranchRef.name`
  (the repository's own instructions may name a different integration branch; use that
  when they do). This is `<base-branch>` in the worker prompt and `- base:` in the state
  file
- the repository path (`<path>` from `forge-detect.sh`, e.g. `owner/repo`): it is
  `<owner/repo>` in the worker prompt and `- repository:` in the state file, and its
  last segment is the repository name in the state file's name; only when the script
  cannot answer, the checkout's directory name
- how the repository verifies changes and any toolchain constraint (CLAUDE.md,
  `.claude/rules/`, `package.json` scripts, `Makefile`, CI configuration): these fill
  `<verification-command>` and `<toolchain-note>` in the worker prompt
- the forge commands for the worker prompt: `<forge-cli>`, `<issue-view-command>`,
  `<pr-list-command>`, and `<pr-create-command>` are the `gh` forms the prompt template
  names on `github`, and the `glab` equivalents from `~/.claude/forge/gitlab.md` on
  `gitlab`

## Options

Remove these tokens from `$ARGUMENTS` before interpreting the rest as Issue numbers.
`--worker-model` takes a value: remove both the flag and the alias that follows it.

### `--merge`

Land each wave's Pull Requests before starting the next wave (step 10).

Without this option, the run stops at Pull Request creation and nothing is merged.

Merging needs a repository where the user can merge without another person's approval.
Where branch protection requires a review, every Pull Request stays `BLOCKED` and
`pr-land` records each one as `PR created, not merged`; that is expected, not a failure.

### `--ignore-checks`

Only meaningful with `--merge`: passed to `pr-land` unchanged, so failing checks do not
stop a merge. For repositories where GitHub Actions cannot run (the account is out of
Actions minutes, or Actions is disabled). Without `--merge` it is ignored and reported
as such. It does not lift a required check; `pr-land` still stops on `BLOCKED`.

### `--dry-run`

Stop after the execution plan (step 6). Write the state file with the plan and a `DONE`
marker, print the Execution plan, Dependencies and conflicts, Not implemented, and
State file sections of the final response, and end. Start no worker, create no branch, change
nothing on GitHub. May be combined with `--merge`; the plan then also shows the merge
order.

### `--resume`

Continue an interrupted run instead of starting a new one (see below). Issue numbers
may be omitted; they come from the state file. Options given on the command line are
added to the options recorded in the state file (so `--resume --merge` turns merging on
for the remaining waves); write the combined set back to the file.

### `--no-merge`

Only with `--resume`: remove `--merge` (and `--ignore-checks`) from the recorded
options, so the remaining waves stop at Pull Request creation. Without `--resume` it
does nothing.

### `--worker-model <alias>`

Run the implementation workers (step 7) on a different model than the session that runs
this orchestrator. `<alias>` is passed as the `model` parameter of each worker's Agent
call and must be one the Agent tool accepts: `opus`, `sonnet`, `haiku`, or `fable`. Any
other value: stop and report before reading the Issues; do not silently drop it or guess.

Without this option, the Agent call carries no `model` and the workers inherit the
session's model (the behaviour before this option existed).

The option changes only the workers. The orchestrator steps (classification, dependency
analysis, waves, `pr-land`, the sweep) run on the session's model regardless. It is
recorded in the state file's `options` line like every other option, shown in the
Execution plan (also under `--dry-run`), and, with `--resume`, a value given on the
command line replaces the recorded one.

Choose the alias for the Issues at hand: workers do the implementation, verification, and
diff review, so a cheaper model pays off on small, well-refined Issues and can cost more
in `pr-fix` rounds on large or vague ones.

# Progress state

A run of this skill can span hours and can be interrupted (the user stops it, or the
client crashes while background workers are running). Keep the plan and the per-Issue
status in a file so the run does not depend on what survives in the conversation.

State file:

```
~/.claude/ship-issues/<repo-name>-<YYYYMMDD-HHMM>.md
```

`<repo-name>` is the GitHub repository name from step 1 (the directory name only when
`gh` cannot answer), `<YYYYMMDD-HHMM>` the time the run started. `work-status.sh`
matches the file to the repository by this prefix and by the `- repository:` header.
Create the directory if it does not exist.

Write the file from the template in `~/.claude/skills/ship-issues/state-file.md`. Read
it and keep its shape exactly: the header lines, the table columns, and the `DONE`
marker are what `~/.claude/scripts/work-status.sh` parses to show this run. A file in
another shape is invisible to `/work-status`.

Write it before starting the workers of a wave, again as each worker finishes, again
when a wave completes, and — with `--merge` — after each merge. A stale state file is
worse than none.

## Stopping on request

If the user asks to stop, finish the workers already running, write the state file, and
report the exact resume command. Do not start another wave.

## Resuming

With `--resume`, find the newest state file for this repository that has no `DONE`
marker and read it. If there is none, stop and report, listing the finished (`DONE`)
files found so the user can tell whether the run they meant already completed.

Do not trust it as fact. Re-establish the real state before continuing:

- for every Issue marked running or done, check for its Pull Request and whether it
  merged. Look it up the way `backlog-review` does, from the strongest signal down:

  ```bash
  gh pr list --state all --limit 300 --json number,state,headRefName,closingIssuesReferences,body
  ```

  A Pull Request belongs to Issue N when its `closingIssuesReferences` names N, else
  when its body says `Closes #N` (or `Fixes` / `Resolves`), else when its `headRefName`
  starts with `N-`. Do not use `gh pr list --search "<N>"`: a full-text search for `31`
  also matches `#310` and misses a Pull Request that only links the Issue through
  `closingIssuesReferences`
- check which worktrees and branches still exist (`git worktree list`, `git branch`)
- only when resuming inside the same session that started the run: check whether a
  recorded Agent task is still alive and can be continued with a message instead of
  restarted. From another session (after a crash) those tasks are unreachable; start
  fresh workers for the unfinished Issues

Then continue from the first unfinished wave. Do not redo completed work, and do not
start a second worker for an Issue that already has a Pull Request.

# 2. Read every Issue

Before starting implementation, read every requested Issue (`gh issue view <N> --comments`).

For each Issue, inspect:

- title
- full body
- relevant comments
- linked Issues
- linked Pull Requests
- acceptance criteria
- explicit scope
- explicit out-of-scope work

Determine whether the Issue is still actionable.

# 3. Check existing implementation work

For every Issue, check whether:

- an open Pull Request already implements it
- a recently merged Pull Request already resolved it
- another branch or Issue appears to duplicate the work
- the Issue is closed or obsolete
- the Issue depends on unresolved work

Do not create competing implementations unnecessarily.

Classify each Issue as one of:

- ready
- already implemented (a merged Pull Request or the code itself already covers it)
- in progress (an open Pull Request already implements it; note its number and whether
  it is a draft)
- blocked
- obsolete
- duplicate
- needs investigation

Do not start a worker for an Issue that is clearly already implemented, in progress,
obsolete, or duplicated. For an in-progress Issue, point at the open Pull Request
(`/pr-review <M>` or `/pr-land <M>`) instead of starting a competing implementation.

Do not start a worker for an Issue that needs investigation either. Report it and
suggest `/issue-refine <N>` so the Issue is made implementable before it is shipped;
do not refine it here.

# 4. Inspect likely implementation impact

For every ready Issue, inspect enough of the repository to estimate its likely implementation footprint.

Consider:

- affected modules
- likely files
- public APIs
- internal APIs
- shared types
- database schemas
- migrations
- generated files
- dependency manifests
- lock files
- global configuration
- routing
- build configuration
- shared test infrastructure
- producer/consumer relationships
- generated clients
- code generation
- deployment configuration

This phase is for dependency and conflict analysis.

Do not implement the Issues.

Do not perform speculative deep implementation work that belongs in the worker context.

# 5. Analyze relationships between Issues

For every pair of ready Issues, determine whether they are:

## Independent

They can reasonably be implemented and merged independently.

## Potentially conflicting

They may modify the same code, shared abstraction, schema, configuration, generated artifact, dependency file, or other common resource.

## Semantically dependent

One Issue relies on behavior, API, schema, type, or infrastructure introduced by another Issue.

## Ordered but independently valuable

Both Issues have independent value, but implementation order materially reduces risk.

Do not treat different file paths as proof of independence.

For example:

- a backend API change and a frontend consumer may be semantically dependent
- separate schema changes may conflict through migration ordering
- different source files may regenerate the same generated artifact
- unrelated features may both modify a central route table
- independent dependencies may both modify the same lock file

# 6. Build an execution plan

Create execution waves.

Issues in the same wave may run concurrently only when they are reasonably safe to implement independently.

Example:

Wave 1:
- #101
- #102
- #104

Wave 2:
- #103, depends on #101

Wave 3:
- #105, likely conflicts with #103

Prefer safe concurrency over maximum concurrency.

Do not serialize Issues without a meaningful reason.

Do not force concurrency when dependencies or shared change surfaces make it risky.

Write the state file now, with every Issue's class and wave.

Under `--dry-run`, this is the end of the run: mark the state file `DONE`, report as
described in "Final response" (Execution plan, Dependencies and conflicts, Not
implemented, State file), and stop. Nothing below runs.

# 7. Delegate each Issue to an isolated worker

For every Issue in the current wave, start a separate implementation worker.

Start each worker with the Agent tool:

- one Agent call per Issue, never one call covering several Issues
- pass `isolation: "worktree"` so the worker gets its own git worktree
- start the workers for a wave in a single message so they run concurrently
- with `--worker-model <alias>`, pass `model: "<alias>"` on every worker's Agent call;
  without it, pass no `model` at all (the template header shows the call shape)
- give each worker exactly one Issue number and instruct it to follow the
  `issue-pr` skill workflow for that Issue

Build the prompt from the template in `~/.claude/skills/ship-issues/worker-prompt.md`.
Read it and fill its slots: the repository facts from step 1 (`<base-branch>`,
`<verification-command>`, `<toolchain-note>`), the Issue and its wave from steps 2–6,
and — when step 12 chose to stack this Issue on an unmerged dependency — that
dependency's branch as `<base-branch>`. Do not improvise the fixed part of the prompt
from run to run.

A worker cannot invoke `issue-pr` as a skill — it is `disable-model-invocation: true`,
so a subagent cannot select it. The template makes the worker read
`~/.claude/skills/issue-pr/SKILL.md` by path instead. Keep it that way.

Workers never merge, regardless of `--merge`. Merging is step 10, in the orchestrator.

Each worker receives exactly one Issue number and works under the constraints listed
in the template (isolated worktree and branch, only its Issue, verification, complete
diff review, commit, push, exactly one Pull Request that references the Issue, no
merge). The template is the single place those constraints live; do not restate a
different list here or in the prompt.

Do not ask one worker to handle multiple Issues.

# 8. Preserve worktree isolation

Each concurrent worker must have its own isolated worktree.

The worktree should be based on an appropriate base branch according to the repository's workflow.

A worker must create its own dedicated branch for the Issue rather than committing onto
the branch the worktree was created on. The worktree's own branch stays unused and is
cleaned up afterwards.

For independent Issues, prefer a fresh base from the remote default branch.

Do not allow a worker to modify:

- another Issue's worktree
- the default-branch checkout
- another worker's branch

If an Issue requires work from another unmerged Issue, do not silently base it on that worker's changes.

Handle the dependency explicitly.

# 9. Monitor worker outcomes

Collect the result of each worker.

For each Issue, record:

- Issue number
- worker status
- the Agent task id and the worktree path the worker used (both go into the state file,
  so `--resume` and `/work-status` can find them)
- branch
- Pull Request URL
- implementation summary
- verification performed
- verification failures
- discovered follow-up work
- discovered dependencies or conflicts

Do not treat worker completion as success unless the expected Pull Request was actually created.

Update the state file as each worker finishes.

# 10. Land the wave's Pull Requests

Only with `--merge`. Without it, skip this step entirely.

After every worker in the wave has finished, land that wave's Pull Requests one at a
time, before reevaluating and before starting the next wave. Merging early keeps later
waves working against a base branch that already contains the earlier work.

For each Pull Request, follow the workflow in `~/.claude/skills/pr-land/SKILL.md`.
Read it by path; `pr-land` is `disable-model-invocation: true` and cannot be selected
as a skill from here. Pass `--ignore-checks` on when it was given.

- one Pull Request at a time, in an order that respects the dependencies found in step 5
- `pr-land` stops on a red light (draft, conflict, failing checks, `CHANGES_REQUESTED`,
  `BLOCKED` by branch protection after the checks are green). When it stops, record the
  Issue as `PR created, not merged (<reason>)` and continue with the remaining Pull
  Requests. Do not override the stop condition. When `pr-land` reports the failing
  checks as billing failures (Actions minutes exhausted), record
  `PR created, not merged (checks failed: billing)` and name
  `/ship-issues --resume --ignore-checks` in the final response.
- do not fix failing checks or review findings here. That is `pr-fix`, run separately
  (`ci-review` first when it is not obvious why a check fails).
- update the state file after each merge

Run `pr-land`'s local cleanup once per wave rather than after every single merge when
that is clearly equivalent; the sweep in step 15 is the backstop either way.

# 11. Reevaluate after each wave

After a wave completes, reevaluate the remaining Issues before starting the next wave.

Check whether completed work changed:

- dependencies
- APIs
- schemas
- migration ordering
- shared types
- generated artifacts
- expected conflict surfaces

If new information invalidates the original plan, update later waves.

Do not blindly follow the initial execution plan.

# 12. Handle dependencies on unmerged Pull Requests

If an Issue depends on another Issue whose Pull Request is not yet merged, choose the safest repository-appropriate option.

Possible outcomes include:

- defer the dependent Issue until the dependency is merged
- explicitly base the dependent branch on the dependency branch: fill `<base-branch>`
  in that worker's prompt with the dependency's branch (not the default branch), so the
  worker's base check and reset target the right ref, and say so in the Pull Request
- report that manual sequencing is required

Do not create a hidden stacked-branch relationship.

If a dependent Pull Request is intentionally stacked, make that dependency explicit in the final report and Pull Request description when appropriate.

Prefer simple independent Pull Requests whenever possible.

# 13. Handle worker failures

If a worker cannot complete its Issue:

- preserve the failure information
- determine whether the cause affects other Issues
- update execution waves if necessary
- continue unrelated Issues when safe

Do not retry indefinitely.

Do not broaden the Issue scope merely to make the worker succeed.

Classify failed work as:

- blocked by dependency
- verification failure
- implementation failure
- ambiguous Issue
- environment/tooling failure
- repository state conflict
- other concrete reason

# 14. Final consistency check

Before completing the orchestration, verify:

- every requested Issue has a final status
- every successfully implemented Issue has exactly one Pull Request
- no Pull Request created by this workflow combines multiple Issues
- no Issue has multiple competing Pull Requests created by this workflow
- blocked Issues are clearly identified
- existing implementations were not duplicated
- dependency relationships are documented
- worker failures are not hidden
- with `--merge`, every Pull Request is either merged or recorded with the reason it was not

# 15. Sweep worker worktrees and branches

Worker worktrees are not auto-removed once the worker has committed, so every run of
this skill leaves worktree directories and unused worktree branches behind.

After all waves have finished, run the sweeper against the repository root (the first
line of `git worktree list`; pass it explicitly, because the sweeper skips a run started
from inside an agent worktree):

```
sh ~/.claude/scripts/worktree-sweep.sh --force <repo-root>
```

`--force` is required here. By default the sweeper skips worktrees touched in the last
60 minutes because an agent may still be running in them, and every worktree this skill
created was touched moments ago, so a plain run removes nothing. All workers have
finished by this point. `--force` relaxes only that timing guard — uncommitted changes,
work that is not on a remote, and live session locks are still kept.

The sweeper only removes what is unambiguously safe. Branches with an open Pull
Request are never touched: their upstream is alive and they are not merged into the
base branch, so they do not match any deletion rule.

If the script is not present, skip this step and note it in the final report.

Report anything the sweeper kept, together with its reason. Do not delete those
items manually. In particular:

- `locked by a running claude session (pid N)` — another session still holds it.
- `in use by another process` — a shell or session has that directory open.

Both need the owning session or shell closed before a re-run. Do not work around them
with `rm -rf`, `git worktree remove --force`, or `git worktree unlock`.

Then mark the state file `DONE` (a line beginning with `DONE`, as in the template).

# Completion status

Use one of the following statuses for each requested Issue. They are derived from the
state file's `class` and `status` columns: an Issue whose class is not `ready` reports
its class (already implemented / in progress / blocked / duplicate / obsolete / needs
investigation) and carries `status: skipped` in the file; a ready Issue reports how far
its worker got.

- PR created
- PR merged (`--merge` only)
- PR created, not merged (`--merge` only; include the reason `pr-land` stopped)
- already implemented
- in progress (name the open Pull Request)
- needs investigation (`/issue-refine <N>` suggested)
- blocked
- deferred
- duplicate
- obsolete
- failed

# Final response

Provide a concise execution report in the following structure.

## Pull Requests

For each successfully implemented Issue:

- Issue number and title
- Pull Request URL
- verification summary
- merge state, when `--merge` was requested

## Not implemented

For each Issue that did not produce a new Pull Request:

- Issue number and title
- status
- reason

## Execution plan

Summarize the waves that were actually executed.

Example:

- Wave 1: #101, #102, #104
- Wave 2: #103 after #101
- Deferred: #105 pending #103 merge

With `--worker-model`, add one line naming the alias the workers ran on.

## Dependencies and conflicts

Report any important:

- stacked Pull Requests
- unresolved dependencies
- likely merge conflicts
- shared migration concerns
- generated-file conflicts
- follow-up sequencing requirements

## State file

The path of the state file, so an interrupted run can be resumed with
`/ship-issues --resume`.

Without `--merge`, do not merge any Pull Request. Under `--dry-run`, say clearly that
no worker was started and nothing was changed.
