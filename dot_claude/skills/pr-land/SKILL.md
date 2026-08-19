---
name: pr-land
description: "Merge a Pull Request that is ready to land: verify checks and review state, merge it, confirm the linked Issue closed, and clean up the local branch and worktree."
argument-hint: "[pr-number] [--keep-branch] [--ignore-checks]"
disable-model-invocation: true
---

Merge the Pull Request identified by `$ARGUMENTS` and clean up after it.

Invoking this skill is the authorization to merge. Do not ask for confirmation again
before merging.

That authorization does not extend to forcing a merge past a problem. Every stop
condition below is a hard stop: report it and end. Do not fix, override, or work
around it here. Fixing review findings and failing checks is the job of `pr-fix`.

All forge operations (reading, searching, merging Pull Requests and reading Issues) go
through the forge CLI: `gh` on GitHub, `glab` on GitLab. Before the first such call, run
`sh ~/.claude/scripts/forge-detect.sh`; it prints one line, `<forge> <host> <path>`. On
`github`, run the `gh` commands below as written. On `gitlab`, read
`~/.claude/forge/gitlab.md` once and run the `glab` equivalent it gives for each `gh`
command below, following its degrade rules where it lists none. If the script fails, stop
and report its message instead of falling back to another client.

# Core rules

- Merge exactly one Pull Request per invocation.
- Never merge a Pull Request that is draft, closed, already merged, or conflicting. Never
  merge one with failing checks unless `--ignore-checks` was given (step 2 says when that
  is appropriate).
- Never merge a Pull Request whose review decision is `CHANGES_REQUESTED`.
- Never push commits to the Pull Request branch. This skill does not modify code.
- Never force-push.
- Never delete a local branch or worktree with your own `git` commands; use the sweeper.
  This does not cover the remote branch of the Pull Request you just merged — step 5
  deletes that one directly.

# 0. Parse the arguments

`--keep-branch` and `--ignore-checks` are options, not a Pull Request number. Remove
them before interpreting the rest.

- `--keep-branch`: leave the remote branch in place after merging (step 5). Without it,
  the remote branch is deleted.
- `--ignore-checks`: failing checks are not a stop condition. This exists for
  repositories where GitHub Actions cannot run — the account is out of Actions minutes
  ("payments have failed or your spending limit needs to be increased") or Actions is
  disabled — so every check fails or never starts and none of that says anything about
  the code. It does not bypass branch protection: when a failing check is *required*,
  GitHub refuses the merge and that stays a stop condition (`mergeStateStatus` =
  `BLOCKED`).

# 1. Resolve the Pull Request number

Normalize what remains of `$ARGUMENTS` into a plain number:

- `82`, `#82`, and a full Pull Request URL all mean Pull Request 82
- strip any leading `#` so the number is never interpolated as `##82`

If nothing remains, resolve the Pull Request for the current branch
(`gh pr view --json number`). If that finds nothing, stop and report.

# 2. Check that it is ready to land

Read the Pull Request state:

```bash
gh pr view <N> --json number,title,state,isDraft,mergeable,mergeStateStatus,reviewDecision,headRefName,baseRefName,isCrossRepository,url
```

Stop and report right away if any of these holds:

- `state` is not `OPEN` (already merged or closed)
- `isDraft` is true
- `reviewDecision` is `CHANGES_REQUESTED` → `/pr-fix <N>` applies the requested changes

`mergeable` is not read yet: right after a push GitHub reports `UNKNOWN`, and it is
re-read after the checks below.

Then wait for the checks:

```bash
gh pr checks <N> --watch
```

Read the output, not the exit code: `gh pr checks` exits 1 when a check failed, 8 while
checks are pending, and 1 with `No checks reported on the '<branch>' branch` when the
Pull Request has no checks at all. None of these is a tool error.

- **No checks reported** → GitHub Actions is disabled for the repository, or it has no
  workflow for this event. Record `checks: none (Actions disabled or no workflows)` and
  continue; there is nothing to wait for.
- **`--watch` cut off** by the tool's timeout → re-read `gh pr checks <N>` without
  `--watch` every few minutes. If checks are still pending after about 30 minutes in
  total, stop and report; do not merge around them.
- **A check failed** → read that run once, without its log:

  ```bash
  gh run view <run-id>
  ```

  (the run id is the number after `/runs/` in the check's link). When the ANNOTATIONS
  section says `The job was not started because recent account payments have failed or
  your spending limit needs to be increased`, the failure is a billing failure: the
  account is out of Actions minutes, the job never ran, and the check says nothing about
  the code. Report it as `checks failed: billing (Actions minutes exhausted)`.

  Without `--ignore-checks`, stop and report the failing checks. Do not merge, and do
  not attempt to fix the failure. Suggest `/pr-land <N> --ignore-checks` when every
  failure is a billing failure; otherwise `/ci-review <N>` to find out why they fail and
  `/pr-fix <N> --checks-only` to fix what the Pull Request caused.

  With `--ignore-checks`, list the failing checks (name, and `billing` when it is one)
  and continue. Say in the report that they were ignored on request.

Only after the checks have finished, read `mergeable` and `mergeStateStatus` again with
the same `gh pr view` call. The order matters: while required checks are still running,
GitHub reports `mergeStateStatus` = `BLOCKED`, and right after a push it reports
`mergeable` = `UNKNOWN`. Neither means anything until the checks are done.

- `mergeable` is `UNKNOWN` → GitHub has not computed it yet. Re-read every few seconds
  for up to about a minute. If it stays `UNKNOWN`, stop and report.
- `mergeStateStatus` is `BLOCKED` (checks green, or ignored) → branch protection is not
  satisfied: a required review, or a required check that failed. Stop and report;
  approval must come from GitHub, and `--ignore-checks` does not lift a required check.
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
branch. For a Pull Request from a fork (`isCrossRepository` is true in step 2), `gh`
skips the remote deletion, and so does this skill: the head branch lives in the fork,
and a branch of the same name in `origin` is not the Pull Request's. Skip the
remote-branch check below entirely and say so in the report.

The order matters. If the local branch is checked out in a worktree (the normal case
when `ship-issues` lands a Pull Request while the worker's worktree still exists),
`git branch -D` fails, `gh` exits non-zero with `failed to delete local branch`, and
**the remote branch is never deleted** even though the merge itself succeeded. Do not
treat this as a stop condition, and do not retry the merge. Instead:

1. Confirm the merge happened: `gh pr view <N> --json state` reports `MERGED`.
2. Note the failed local deletion. The sweeper in step 7 handles the local branch; do
   not delete it yourself.
3. Continue with the remote-branch check below.

After the merge, unless `--keep-branch` was given or the Pull Request is from a fork,
make sure the remote branch is really gone rather than trusting the exit code:

```bash
git ls-remote --exit-code --heads origin <headRefName>
```

Exit code 0 means the branch still exists (2 means it is gone). If it still exists,
delete it:

```bash
git push origin --delete <headRefName>
```

Take `<headRefName>` from step 2.

This is the one place where deleting a branch with your own `git` command is correct: it
is the remote branch of a Pull Request you just merged, not a local branch or a worktree,
so it is not the sweeper's job. Use `git ls-remote` and `git push origin --delete`, not
`gh api` or `glab api`: the read form is not in the permission allow-list and prompts
every time, and the `-X DELETE` form gets blocked by the permission classifier.

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
- check results at merge time: passed, `none (Actions disabled or no workflows)`, or the
  failing checks that `--ignore-checks` skipped (naming billing failures as such)
- local cleanup result, including everything the sweeper kept and why
- if the merge did not happen: the exact stop condition and what has to happen first
