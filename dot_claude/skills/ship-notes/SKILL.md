---
name: ship-notes
description: "Turn bug and idea notes into well-scoped GitHub Issues, plan safe parallel execution, and delegate each Issue to an isolated worker that creates exactly one Pull Request."
argument-hint: "[notes-file-or-text]"
disable-model-invocation: true
---

Process the notes provided in `$ARGUMENTS` from triage through Pull Request creation.

This skill is an orchestrator.

Do not implement multiple Issues directly in the orchestrator context.

The workflow must preserve the boundary:

Notes
→ investigation
→ GitHub Issues
→ isolated Issue workers
→ Pull Requests

# Global principles

- Issue design and implementation are separate phases.
- One Issue corresponds to exactly one Pull Request.
- One implementation worker handles exactly one Issue.
- Independent Issues should run in parallel when safe.
- Dependent or conflicting Issues must run in ordered waves.
- Each implementation must use an isolated branch/worktree.
- The orchestrator should retain only coordination context, not detailed implementation context.
- Do not merge Pull Requests.

# Phase 1: Triage the notes

Perform the same process as the `triage-notes` skill.

For every note:

1. understand the intent
2. inspect the relevant repository code
3. search existing Issues and Pull Requests
4. identify the actual behavior or feature boundary
5. decide whether it should become:
   - one Issue
   - multiple Issues
   - part of another Issue
   - no new Issue because it is a duplicate
   - no Issue because it is not actionable
6. create independently meaningful and mergeable Issues

Do not implement anything during this phase.

# Phase 2: Freeze the Issue boundary

Once an Issue is created, treat it as the scope contract for its implementation worker.

Do not rewrite Issue requirements merely to make implementation easier.

If later investigation reveals that the Issue is materially incorrect or impossible as written, report that condition instead of silently changing the intended scope.

# Phase 3: Analyze implementation relationships

For every created Issue, estimate likely impact areas.

Consider:

- modules
- files
- APIs
- shared types
- database schemas
- migrations
- generated files
- dependency manifests
- lock files
- global configuration
- producer/consumer relationships
- feature dependencies

Build a dependency graph.

Classify Issues into execution waves.

Issues may run in the same wave only when they are reasonably safe to implement independently.

File non-overlap alone is not sufficient evidence of independence.

# Phase 4: Delegate Issue implementation

For each Issue in the current execution wave, start an independent implementation worker.

Start each worker with the Agent tool:

- one Agent call per Issue, never one call covering several Issues
- pass `isolation: "worktree"` so the worker gets its own git worktree
- start the workers for a wave in a single message so they run concurrently
- give each worker exactly one Issue number and instruct it to follow the
  `issue-pr` skill workflow for that Issue

Each worker must:

- receive exactly one Issue number
- operate in its own isolated branch/worktree
- read the Issue independently
- inspect the code independently
- implement only that Issue
- follow the same workflow as the `issue-pr` skill
- run relevant verification
- review its own diff
- push its branch
- create exactly one Pull Request
- not merge the Pull Request

Do not ask one worker to implement multiple Issues.

Do not allow workers to share a mutable worktree.

Prefer concurrent workers for Issues in the same safe execution wave.

# Phase 5: Collect results

For each worker, collect:

- Issue number
- Pull Request URL
- implementation status
- verification status
- relevant failures
- newly discovered dependencies
- conflicts with other Issues

If a worker discovers a dependency that invalidates the current execution plan, update later waves accordingly.

Do not hide failures.

# Phase 6: Continue dependent waves

After the current wave completes, reevaluate remaining Issues.

If an Issue depends on an unmerged Pull Request, determine whether it should:

- wait
- branch from the dependency branch when repository workflow permits it
- be deferred until the dependency is merged

Do not silently implement against assumptions that are not present in its base branch.

Prefer simple, reviewable dependency handling over maximizing concurrency.

# Phase 7: Final consistency check

When all possible workers have completed, verify:

- every created actionable Issue has exactly one corresponding Pull Request, unless explicitly blocked
- no Issue has multiple competing Pull Requests created by this workflow
- no Pull Request combines multiple Issues
- known dependencies are reported
- failed or blocked Issues are clearly identified
- duplicate or rejected notes were not accidentally implemented

# Final response

Provide a concise execution report.

Include:

## Created Issues

For each created Issue:

- Issue number
- title
- URL

## Pull Requests

For each implemented Issue:

- Issue number
- Pull Request URL
- status
- verification summary

## Not created

List:

- duplicate notes
- merged notes
- non-actionable notes

## Blocked or deferred

List any Issues that could not safely proceed and explain why.

## Execution waves

Summarize the parallelization/dependency plan actually used.

Do not merge any Pull Request.
