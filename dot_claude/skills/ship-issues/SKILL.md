---
name: ship-issues
description: "Orchestrate implementation of multiple existing GitHub Issues by analyzing dependencies, planning safe parallel execution, and delegating each Issue to an isolated worker that creates exactly one Pull Request."
argument-hint: "[issue-numbers...] [--merge] [--resume]"
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
- All GitHub operations (reading, searching, and creating Issues and Pull Requests) go through the GitHub CLI (`gh`). Do not use another GitHub client. If `gh` is unavailable or not authenticated, stop and report instead of falling back.

# 1. Parse the requested Issues

Interpret `$ARGUMENTS` as the set of GitHub Issue numbers to process, plus options.

Accept common forms such as:

- `101 102 103`
- `#101 #102 #103`
- `101,102,103`

Strip any leading `#` so a number is never interpolated as `##101`.

Normalize the input into a unique Issue list.

Do not process unrelated Issues that were not requested.

## Options

Remove these tokens from `$ARGUMENTS` before interpreting the rest as Issue numbers.

### `--merge`

Land each wave's Pull Requests before starting the next wave (step 10).

Without this option, the run stops at Pull Request creation and nothing is merged.

### `--resume`

Continue an interrupted run instead of starting a new one (see below). Issue numbers
may be omitted; they come from the state file.

# Progress state

A run of this skill can span hours and can be interrupted (the user stops it, or the
client crashes while background workers are running). Keep the plan and the per-Issue
status in a file so the run does not depend on what survives in the conversation.

State file:

```
~/.claude/ship-issues/<repo-name>-<YYYYMMDD-HHMM>.md
```

`<repo-name>` is the repository name, `<YYYYMMDD-HHMM>` the time the run started.
Create the directory if it does not exist.

Record:

- repository, base branch, the requested Issue list, and the options in effect
- each Issue's classification from step 3
- the wave plan from step 6
- per Issue: status, branch, worktree path, Agent task id, Pull Request URL, merge state, notes
- a `DONE` marker once step 15 has finished

Write it before starting the workers of a wave, again as each worker finishes, again
when a wave completes, and — with `--merge` — after each merge. A stale state file is
worse than none.

## Stopping on request

If the user asks to stop, finish the workers already running, write the state file, and
report the exact resume command. Do not start another wave.

## Resuming

With `--resume`, find the newest state file for this repository that has no `DONE`
marker and read it.

Do not trust it as fact. Re-establish the real state before continuing:

- for every Issue marked in progress or done, check for its Pull Request
  (`gh pr list --search "<N>" --state all`) and whether it merged
- check which worktrees and branches still exist (`git worktree list`, `git branch`)
- check whether any recorded Agent task is still alive and can be resumed with a message
  instead of restarted from scratch

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
- already implemented
- blocked
- obsolete
- duplicate
- needs investigation

Do not start a worker for an Issue that is clearly already implemented, obsolete, or duplicated.

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

# 7. Delegate each Issue to an isolated worker

For every Issue in the current wave, start a separate implementation worker.

Start each worker with the Agent tool:

- one Agent call per Issue, never one call covering several Issues
- pass `isolation: "worktree"` so the worker gets its own git worktree
- start the workers for a wave in a single message so they run concurrently
- give each worker exactly one Issue number and instruct it to follow the
  `issue-pr` skill workflow for that Issue

Build the prompt from the template in `~/.claude/skills/ship-issues/worker-prompt.md`.
Read it and fill its slots from the analysis in steps 2-6. Do not improvise the fixed
part of the prompt from run to run.

A worker cannot invoke `issue-pr` as a skill — it is `disable-model-invocation: true`,
so a subagent cannot select it. The template makes the worker read
`~/.claude/skills/issue-pr/SKILL.md` by path instead. Keep it that way.

Workers never merge, regardless of `--merge`. Merging is step 10, in the orchestrator.

Each worker must receive exactly one Issue number.

Each worker must:

- operate in an isolated branch/worktree
- read the Issue independently
- inspect the relevant implementation independently
- follow repository-specific instructions
- implement only its assigned Issue
- run relevant verification
- review its complete diff
- commit the implementation
- push its branch
- create exactly one Pull Request
- reference the Issue from the Pull Request
- not merge the Pull Request

The worker should follow the repository's `issue-pr` workflow when that skill is available.

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
as a skill from here.

- one Pull Request at a time, in an order that respects the dependencies found in step 5
- `pr-land` stops on a red light (draft, conflict, failing checks, `CHANGES_REQUESTED`).
  When it stops, record the Issue as `PR created, not merged (<reason>)` and continue
  with the remaining Pull Requests. Do not override the stop condition.
- do not fix failing checks or review findings here. That is `pr-fix`, run separately.
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
- explicitly base the dependent branch on the dependency branch
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

After all waves have finished, run the sweeper against the repository root:

```
sh ~/.claude/scripts/worktree-sweep.sh --force
```

`--force` is required here. By default the sweeper skips worktrees touched in the last
60 minutes because an agent may still be running in them, and every worktree this skill
created was touched moments ago, so a plain run removes nothing. All workers have
finished by this point. `--force` relaxes only that timing guard — uncommitted changes,
work that is not on a remote, and live session locks are still kept.

The sweeper only removes what is unambiguously safe. Branches with an open Pull
Request are never touched: their upstream is alive and they are not merged into the
base branch, so they do not match any deletion rule.

If the script is not present, skip this step silently and note it in the final report.

Report anything the sweeper kept, together with its reason. Do not delete those
items manually. In particular:

- `locked by a running claude session (pid N)` — another session still holds it.
- `in use by another process` — a shell or session has that directory open.

Both need the owning session or shell closed before a re-run. Do not work around them
with `rm -rf`, `git worktree remove --force`, or `git worktree unlock`.

Then mark the state file `DONE`.

# Completion status

Use one of the following statuses for each requested Issue:

- PR created
- PR merged (`--merge` only)
- PR created, not merged (`--merge` only; include the reason `pr-land` stopped)
- already implemented
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

Without `--merge`, do not merge any Pull Request.
