---
name: ship-issues
description: "Orchestrate implementation of multiple existing GitHub Issues by analyzing dependencies, planning safe parallel execution, and delegating each Issue to an isolated worker that creates exactly one Pull Request."
argument-hint: "[issue-numbers...]"
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
- Do not merge Pull Requests.
- Keep detailed implementation work out of the orchestrator context.

# 1. Parse the requested Issues

Interpret `$ARGUMENTS` as the set of GitHub Issue numbers to process.

Accept common forms such as:

- `101 102 103`
- `#101 #102 #103`
- `101,102,103`

Normalize the input into a unique Issue list.

Do not process unrelated Issues that were not requested.

# 2. Read every Issue

Before starting implementation, read every requested Issue.

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

# 10. Reevaluate after each wave

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

# 11. Handle dependencies on unmerged Pull Requests

If an Issue depends on another Issue whose Pull Request is not yet merged, choose the safest repository-appropriate option.

Possible outcomes include:

- defer the dependent Issue until the dependency is merged
- explicitly base the dependent branch on the dependency branch
- report that manual sequencing is required

Do not create a hidden stacked-branch relationship.

If a dependent Pull Request is intentionally stacked, make that dependency explicit in the final report and Pull Request description when appropriate.

Prefer simple independent Pull Requests whenever possible.

# 12. Handle worker failures

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

# 13. Final consistency check

Before completing the orchestration, verify:

- every requested Issue has a final status
- every successfully implemented Issue has exactly one Pull Request
- no Pull Request created by this workflow combines multiple Issues
- no Issue has multiple competing Pull Requests created by this workflow
- blocked Issues are clearly identified
- existing implementations were not duplicated
- dependency relationships are documented
- worker failures are not hidden

# Completion status

Use one of the following statuses for each requested Issue:

- PR created
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

Do not merge any Pull Request.
