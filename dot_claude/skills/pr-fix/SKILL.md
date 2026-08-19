---
name: pr-fix
description: "Apply review findings, failing checks, and base-branch conflicts to an existing Pull Request branch: decide which findings to accept, fix them, verify, commit, and push without merging."
argument-hint: "[pr-number] [--checks-only] [findings...]"
disable-model-invocation: true
---

Apply review findings to the Pull Request identified by the first token of `$ARGUMENTS`.
"Findings" here also covers what GitHub itself reports against the Pull Request: failing
checks and conflicts with the base branch.

This skill modifies the Pull Request branch. It does not merge, and it does not post
anything to GitHub.

All forge operations (reading, searching, and updating Issues and Pull Requests) go
through the forge CLI: `gh` on GitHub, `glab` on GitLab. Before the first such call, run
`sh ~/.claude/scripts/forge-detect.sh`; it prints one line, `<forge> <host> <path>`. On
`github`, run the `gh` commands below as written. On `gitlab`, read
`~/.claude/forge/gitlab.md` once and run the `glab` equivalent it gives for each `gh`
command below, following its degrade rules where it lists none. If the script fails, stop
and report its message instead of falling back to another client.

# Core rules

- Fix only what the findings call for, plus what is required to make those fixes correct.
- Do not accept a finding blindly. Verify each one against the code before acting on it.
- Do not silently ignore a finding either. Every finding ends as fixed or declined with a reason.
- Do not expand the scope of the Pull Request. A finding that asks for work outside the Pull Request's Issue is declined and reported.
- Never weaken tests or validation merely to make the change pass.
- Never modify the default-branch checkout.
- Never force-push.
- Never merge the Pull Request. Landing it is `pr-land`'s job.
- Do not post comments or reviews to GitHub. Return the result in the conversation.

# 1. Resolve the Pull Request number

`--checks-only` is an option, not a Pull Request number. Remove it before interpreting
the rest. With it, only what GitHub reports against the branch is a finding: a
`ci-review` classification from this conversation (source 2b), base-branch conflicts
(source 4), and failing checks (source 5). Review findings (sources 1, 2a, and 3) are
not collected, even when they exist; leave them for a later plain `/pr-fix`. When
free-form text was also given, say in the report that it was ignored because of
`--checks-only`.

Normalize the first token of what remains into a plain number:

- `82`, `#82`, and a full Pull Request URL all mean Pull Request 82
- strip any leading `#` so the number is never interpolated as `##82`

Everything after that token is free-form finding text from the user.

If no number is given, resolve the Pull Request for the current branch
(`gh pr view --json number`). If that finds nothing, stop and report.

Then confirm the Pull Request can still take commits:

```bash
gh pr view <N> --json state,isDraft
```

If `state` is not `OPEN` (merged or closed), stop and report; there is no branch to fix.
A draft is fine.

# 2. Collect the findings

Gather findings from these sources, in order:

1. the free-form text remaining in `$ARGUMENTS`
2. results produced earlier in this same conversation:
   - 2a. a `pr-review` result: its findings, by severity
   - 2b. a `ci-review` result: every `pr-caused` row is a finding. Rows classified
     `pre-existing`, `flaky`, `infrastructure` (including `billing`), or
     `ci-definition` are not findings to fix: carry them into the report as declined
     with `ci-review`'s evidence, and do not re-investigate them in source 5. Rows
     classified `needs investigation` carry no verdict: handle those checks in source 5
     as if `ci-review` had not seen them
3. review state on GitHub:

```bash
gh pr view <N> --comments
```

This includes a review that `pr-review --post` left as a Pull Request comment (it
starts with a verdict line: `APPROVE` / `REQUEST CHANGES` / `COMMENT`). Treat its
findings like a human review. For inline review comments, read them with a GET request
only:

```bash
gh api "repos/<path>/pulls/<N>/comments" --paginate
```

(`<path>` is what `forge-detect.sh` printed.) This is the one `gh api` call in these
skills, because `gh` has no other way to list inline review comments. It is not in the
permission allow-list, so it prompts every time; skip it when the user declines and say
so. Never use `gh api` (or `glab api`) with a method that writes; on GitLab the read
form is `glab api -X GET`, as `gitlab.md` gives it.

4. conflicts with the base branch:

```bash
gh pr view <N> --json mergeable,mergeStateStatus,baseRefName
```

`mergeable` = `CONFLICTING` or `mergeStateStatus` = `DIRTY` is a finding: "resolve the
conflicts with `<base>`". `mergeStateStatus` = `BEHIND` is a finding only when the
repository requires branches to be up to date before merging (`gh pr merge` refuses,
or the protection rule says so); otherwise note it and leave it.

5. failing checks:

```bash
gh pr checks <N>
```

Read its output, not its exit code (1 when a check failed, 8 while pending, 1 with `No
checks reported on the '<branch>' branch` when there are none). `No checks reported`
means Actions is disabled or has no workflow for this event: there is nothing to fix
from this source.

Every failing check is a finding. Read the failing run's log with
`gh run view <run-id> --log-failed` (the run id is in the check's URL) before deciding
whether the failure is caused by this Pull Request. `log not found` means the job never
ran; `gh run view <run-id>` then shows why in ANNOTATIONS. `The job was not started
because recent account payments have failed or your spending limit needs to be
increased` is a billing failure (the account is out of Actions minutes): decline it, it
says nothing about the code, and name `/pr-land <N> --ignore-checks` in the report as
the way to land the Pull Request while Actions cannot run. When a `ci-review` result
from source 2b already classified the check, use that classification instead of reading
the log again. When the cause is unclear and there are several failing checks,
`/ci-review <N>` first is the cheaper path; this skill only needs to know which
failures are the Pull Request's own.

If all sources are empty (or, with `--checks-only`, sources 2b, 4, and 5), stop and
report that there is nothing to fix. Do not invent work.

List the collected findings before changing anything, so the set being acted on is
explicit.

# 3. Get onto the Pull Request branch

Determine the Pull Request's head branch (`gh pr view <N> --json headRefName`), then
where that branch is checked out (`git worktree list`).

- Already on that branch, in a checkout that is not the default-branch checkout →
  continue there.
- The branch is checked out in another worktree (the usual case after `ship-issues`:
  the worker's worktree under `.claude/worktrees/` still holds it) → work in that
  worktree. `cd` there or prefix commands with `git -C <path>`; do not create a second
  worktree, because `gh pr checkout` would fail with `already checked out at …`. Do not
  start if the worktree has uncommitted changes that are not yours: report and stop.
- Nowhere → work in an isolated worktree. Use the EnterWorktree tool with the name
  `pr-<N>`, then check the Pull Request out into it:

```bash
gh pr checkout <N>
```

Never edit the default-branch checkout.

Confirm the branch is up to date with its remote (`git fetch origin` and compare) before
editing. If the remote branch has commits the local one lacks, fast-forward first. If the
branch has diverged, stop and report; do not resolve it by force.

# 4. Read the Pull Request and its Issue

Read the Pull Request body and the linked Issue.

The Issue is the scope boundary. A finding is in scope when fixing it keeps the Pull
Request inside that boundary.

# 5. Triage each finding

For every finding, decide one of:

- **fix** — the finding is correct and in scope
- **decline** — with a concrete reason, such as:
  - the finding is factually wrong (say what the code actually does)
  - the behavior is intentional and required by the Issue
  - the fix belongs to a separate Issue because it exceeds this Pull Request's scope
  - it is a stylistic preference the repository does not require

Read enough surrounding code to make this judgment. Do not rely on the finding's own
description of the code.

Declining is a legitimate outcome. Report it; do not quietly skip.

# 6. Fix

Implement the smallest correct fix for each accepted finding.

Follow repository conventions. When a finding is about a defect in behavior, add or
update a regression test when the repository's conventions warrant it.

Do not take the opportunity to refactor, reformat, rename, or upgrade dependencies.

For a conflict with the base branch, merge the base into the head branch and resolve
the conflicts there:

```bash
git fetch origin
git merge origin/<base>
```

Never rebase: the branch is already pushed, and rewriting it would need a force-push.
Resolve each conflict by reading both sides and the Issue; do not pick one side
mechanically. Regenerate generated files with the repository's tooling rather than
resolving them by hand. Verification (step 7) runs against the merged result.

For a failing check, fix it only when the log shows the failure comes from this Pull
Request. A failure that also happens on the base branch is pre-existing: decline it,
say so in the report, and do not modify unrelated code to make the check green. A
`ci-review` classification, when there is one, settles this: fix `pr-caused`, decline
the rest with its evidence (a `billing` failure with the `/pr-land <N> --ignore-checks`
note). Do not re-run a flaky check from here (`gh run rerun` is a GitHub write); name it
in the report so the user can.

# 7. Verify

Find the verification the repository defines: CLAUDE.md, `.claude/rules/`,
`package.json` scripts, `Makefile`, CI configuration, or similar.

Run focused verification first (affected tests, type checking for the affected package,
targeted linting), then the broader verification the repository requires.

Do not invent generic verification commands when the repository already defines its own.
If the repository defines none, say so and do not fabricate results.

If verification fails:

1. determine whether this change caused the failure
2. fix failures caused by this change
3. do not modify unrelated code to repair pre-existing failures

Record pre-existing failures for the final report.

# 8. Review the new diff

Inspect the diff produced in this session before committing.

Check for changes unrelated to the accepted findings, debugging code, temporary files,
accidental generated-file or lock-file changes, secrets, and machine-specific paths.

Remove anything that does not belong.

# 9. Commit and push

Commit following the `cm` skill workflow:

- group by logical theme; one theme, one commit
- stage files explicitly; never `git add -A` or `git add .`
- Conventional Commits format, with the subject in the language of the repository's
  existing commits (Japanese when the repository has no established convention)
- no tool traces, no co-author trailers

A base-branch merge commit produced in step 6 is kept as it is; do not squash or reword
it.

Push to the existing remote branch. Do not force-push. Do not push to the default branch.

# Final response

Do not merge. Do not post to GitHub. Return:

- Pull Request number and URL
- findings fixed, each with what changed
- findings declined, each with the reason (a billing check failure names
  `/pr-land <N> --ignore-checks`)
- free-form findings ignored because of `--checks-only`, if any
- conflicts resolved (files) and checks addressed, if any
- verification run and its result, including pre-existing failures
- the pushed branch and commits
- follow-up work that should become a separate Issue
