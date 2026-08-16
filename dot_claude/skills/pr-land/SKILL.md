---
name: pr-land
description: "Merge a Pull Request that is ready to land: verify checks and review state, merge it, confirm the linked Issue closed, and clean up the local branch and worktree."
argument-hint: "[pr-number]"
disable-model-invocation: true
---

Merge the Pull Request identified by `$ARGUMENTS` and clean up after it.

Invoking this skill is the authorization to merge. Do not ask for confirmation again
before merging.

That authorization does not extend to forcing a merge past a problem. Every stop
condition below is a hard stop: report it and end. Do not fix, override, or work
around it here. Fixing review findings and failing checks is the job of `pr-fix`.

All GitHub operations (reading, searching, merging Pull Requests and reading Issues) go through the GitHub CLI (`gh`). Do not use another GitHub client. If `gh` is unavailable or not authenticated, stop and report instead of falling back.

# Core rules

- Merge exactly one Pull Request per invocation.
- Never merge a Pull Request that is draft, closed, already merged, conflicting, or has failing checks.
- Never merge a Pull Request whose review decision is `CHANGES_REQUESTED`.
- Never push commits to the Pull Request branch. This skill does not modify code.
- Never force-push.
- Never delete a local branch or worktree with your own `git` commands; use the sweeper.

# 1. Resolve the Pull Request number

Normalize `$ARGUMENTS` into a plain number:

- `82`, `#82`, and a full Pull Request URL all mean Pull Request 82
- strip any leading `#` so the number is never interpolated as `##82`

If `$ARGUMENTS` is empty, resolve the Pull Request for the current branch
(`gh pr view --json number`). If that finds nothing, stop and report.

# 2. Check that it is ready to land

Read the Pull Request state:

```bash
gh pr view <N> --json number,title,state,isDraft,mergeable,mergeStateStatus,reviewDecision,headRefName,baseRefName,url
```

Stop and report if any of these holds:

- `state` is not `OPEN` (already merged or closed)
- `isDraft` is true
- `mergeable` is `CONFLICTING`
- `reviewDecision` is `CHANGES_REQUESTED`
- `mergeStateStatus` is `BLOCKED` or `DIRTY`

Then wait for the checks:

```bash
gh pr checks <N> --watch
```

If any required check fails, stop and report the failing checks. Do not merge, and do
not attempt to fix the failure.

If the repository has no checks at all, say so and continue.

# 3. Read the Pull Request before merging

Read the Pull Request body and the linked Issue (`gh pr view <N> --comments`).

Confirm:

- what is about to be merged
- which Issue it closes, if any
- whether review comments contain unresolved objections that the review decision does not reflect

If the discussion clearly contains unaddressed objections, stop and report rather than
merging on a technicality.

# 4. Choose the merge method

Follow the repository's convention:

- explicit instructions in CLAUDE.md, `.claude/rules/`, or `CONTRIBUTING.md`
- otherwise the method used by recently merged Pull Requests (`gh pr list --state merged --limit 10 --json number,title`, and the shape of the resulting commits on the base branch)

Check which methods the repository actually allows:

```bash
gh repo view --json squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed
```

Use `--squash` when the convention is unclear and squash merging is allowed.

# 5. Merge

```bash
gh pr merge <N> --squash --delete-branch
```

Replace `--squash` with the method chosen in step 4.

`--delete-branch` removes the remote branch and, when the local branch is checked out
somewhere, the local one as well.

For a squash merge, make sure the resulting commit message follows the repository's
commit convention. Do not leave tool traces, co-author trailers, or generated-by
boilerplate in it.

If the merge command fails, report the error and stop. Do not retry with a different
method to get past a rejection.

# 6. Confirm the outcome

Verify:

- the Pull Request is merged (`gh pr view <N> --json state,mergedAt,mergeCommit`)
- the linked Issue is closed (`gh issue view <N> --json state`); if it is still open, report it — do not close it manually unless the user asks

# 7. Clean up locally

If the current checkout is on the merged branch, switch to the base branch first.

Then update the base branch:

```bash
git fetch --prune
git pull --ff-only
```

If `git pull --ff-only` fails, leave it and report; do not merge or rebase to force it.

Then sweep leftover worktrees and branches:

```bash
sh ~/.claude/scripts/worktree-sweep.sh
```

If the script is not present, skip this step and note it in the report. Do not delete
worktrees or branches with your own `git` commands.

Report everything the sweeper kept, together with its reason.

# Final response

Return:

- Pull Request number, title, and merge commit
- merge method used
- the Issue that closed, or a note that it did not
- check results at merge time
- local cleanup result, including everything the sweeper kept and why
- if the merge did not happen: the exact stop condition and what has to happen first
