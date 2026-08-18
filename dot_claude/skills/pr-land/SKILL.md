---
name: pr-land
description: "Merge a Pull Request that is ready to land: verify checks and review state, merge it, confirm the linked Issue closed, and clean up the local branch and worktree."
argument-hint: "[pr-number] [--keep-branch]"
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
  This does not cover the remote branch of the Pull Request you just merged — step 5
  deletes that one directly.

# 0. Parse the arguments

`--keep-branch` is an option, not a Pull Request number. Remove it before interpreting
the rest. With it, leave the remote branch in place after merging (step 5). Without it,
the remote branch is deleted.

# 1. Resolve the Pull Request number

Normalize what remains of `$ARGUMENTS` into a plain number:

- `82`, `#82`, and a full Pull Request URL all mean Pull Request 82
- strip any leading `#` so the number is never interpolated as `##82`

If nothing remains, resolve the Pull Request for the current branch
(`gh pr view --json number`). If that finds nothing, stop and report.

# 2. Check that it is ready to land

Read the Pull Request state:

```bash
gh pr view <N> --json number,title,state,isDraft,mergeable,mergeStateStatus,reviewDecision,headRefName,baseRefName,url
```

Stop and report right away if any of these holds:

- `state` is not `OPEN` (already merged or closed)
- `isDraft` is true
- `mergeable` is `CONFLICTING`
- `reviewDecision` is `CHANGES_REQUESTED`

Then wait for the checks:

```bash
gh pr checks <N> --watch
```

If any required check fails, stop and report the failing checks. Do not merge, and do
not attempt to fix the failure.

If the repository has no checks at all, say so and continue.

Only after the checks have finished, read `mergeable` and `mergeStateStatus` again with
the same `gh pr view` call. The order matters: while required checks are still running,
GitHub reports `mergeStateStatus` = `BLOCKED`, and right after a push it reports
`mergeable` = `UNKNOWN`. Neither means anything until the checks are done.

- `mergeable` is `UNKNOWN` → GitHub has not computed it yet. Re-read every few seconds
  for up to about a minute. If it stays `UNKNOWN`, stop and report.
- `mergeStateStatus` is `BLOCKED` (checks green) → branch protection is not satisfied,
  usually a required review. Stop and report; approval must come from GitHub.
- `mergeStateStatus` is `DIRTY` or `mergeable` is `CONFLICTING` → stop and report;
  `/pr-fix <N>` resolves the conflict.
- `mergeStateStatus` is `BEHIND` and the repository requires branches to be up to date
  → stop and report; `/pr-fix <N>` brings the branch up to date. When the repository
  does not require it, `BEHIND` is not a stop condition.

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
gh pr merge <N> --squash --delete-branch --subject "<subject>" --body "<body>"
```

Replace `--squash` with the method chosen in step 4.

For a squash merge, `gh` would otherwise build the commit from the Pull Request title
and the list of commit headlines. Pass the message explicitly so the squash commit
follows the repository's commit convention: `--subject` in the Conventional Commits
form the repository uses (`<type>(<scope>): <subject> (#<N>)`, taking the type from
the Pull Request title or its commits, in the language of the existing commits) and
`--body` with the why, taken from the Pull Request body. Do not leave tool traces,
co-author trailers, or generated-by boilerplate in either. For a merge commit or a
rebase merge, omit `--subject` / `--body`.

With `--keep-branch`, drop `--delete-branch` and leave the remote branch in place:

```bash
gh pr merge <N> --squash --subject "<subject>" --body "<body>"
```

`--delete-branch` makes `gh` delete, in this order: the local branch of the same name if
one exists (switching to the base branch first when it is checked out), then the remote
branch. For a Pull Request from a fork, `gh` skips the remote deletion.

The order matters. If the local branch is checked out in a worktree (the normal case
when `ship-issues` lands a Pull Request while the worker's worktree still exists),
`git branch -D` fails, `gh` exits non-zero with `failed to delete local branch`, and
**the remote branch is never deleted** even though the merge itself succeeded. Do not
treat this as a stop condition, and do not retry the merge. Instead:

1. Confirm the merge happened: `gh pr view <N> --json state` reports `MERGED`.
2. Note the failed local deletion. The sweeper in step 7 handles the local branch; do
   not delete it yourself.
3. Continue with the remote-branch check below.

After the merge, unless `--keep-branch` was given, make sure the remote branch is really
gone rather than trusting the exit code:

```bash
git ls-remote --exit-code --heads origin <headRefName>
```

Exit code 0 means the branch still exists (2 means it is gone). If it still exists and
the Pull Request is not from a fork, delete it:

```bash
git push origin --delete <headRefName>
```

Take `<headRefName>` from step 2. Deleting several at once is fine — pass them all to a
single `git push origin --delete`.

This is the one place where deleting a branch with your own `git` command is correct: it
is the remote branch of a Pull Request you just merged, not a local branch or a worktree,
so it is not the sweeper's job. Use `git ls-remote` and `git push origin --delete`, not
`gh api`: the read form is not in the permission allow-list and prompts every time, and
the `-X DELETE` form gets blocked by the permission classifier.

If the delete is rejected (for example by branch protection), report it and continue; do
not force it.

`--keep-branch` only affects the remote branch. Local cleanup in step 7 is unchanged, and
the sweeper may still remove the merged local branch.

If the merge itself fails (the Pull Request is not `MERGED` afterwards), report the error
and stop. Do not retry with a different method to get past a rejection.

# 6. Confirm the outcome

Verify:

- the Pull Request is merged (`gh pr view <N> --json state,mergedAt,mergeCommit`)
- the linked Issue is closed (`gh issue view <issue-number> --json state`, the Issue
  from step 3, not the Pull Request number); if it is still open, report it — do not
  close it manually unless the user asks

# 7. Clean up locally

Find the main worktree first: the first line of `git worktree list` is the repository's
main checkout. Two cases:

- **The current directory is the main checkout.** If it is on the merged branch, switch
  to the base branch. Then update the base branch:

  ```bash
  git fetch --prune
  git pull --ff-only
  ```

- **The current directory is inside an agent worktree** (under `.claude/worktrees/`;
  this happens when `issue-pr --merge` or `pr-ready --merge` ran from a session that
  entered the worktree with EnterWorktree). Do not switch branches here — the base
  branch is checked out in the main worktree and cannot be checked out twice. Update the
  base branch from the main checkout instead:

  ```bash
  git -C <main-root> fetch --prune
  git -C <main-root> pull --ff-only
  ```

  The current worktree itself is left in place: the sweeper keeps a worktree the session
  is inside (`the current session is inside it`). Say so in the report; it goes on the
  next `/worktree-sweep` from the main checkout, or the sweep in `ship-issues` step 15.

If `git pull --ff-only` fails, leave it and report; do not merge or rebase to force it.

Then sweep leftover worktrees and branches, from the main checkout:

```bash
sh ~/.claude/scripts/worktree-sweep.sh <main-root>
```

If the script is not present, skip this step and note it in the report. Do not delete
worktrees or branches with your own `git` commands.

Report everything the sweeper kept, together with its reason.

# Final response

Return:

- Pull Request number, title, and merge commit
- merge method used
- whether the remote branch was deleted or kept (`--keep-branch`)
- the Issue that closed, or a note that it did not
- check results at merge time
- local cleanup result, including everything the sweeper kept and why
- if the merge did not happen: the exact stop condition and what has to happen first
