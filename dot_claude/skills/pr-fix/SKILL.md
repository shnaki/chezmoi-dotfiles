---
name: pr-fix
description: "Apply review findings to an existing Pull Request branch: decide which findings to accept, fix them, verify, commit, and push without merging."
argument-hint: "[pr-number] [findings...]"
disable-model-invocation: true
---

Apply review findings to the Pull Request identified by the first token of `$ARGUMENTS`.

This skill modifies the Pull Request branch. It does not merge, and it does not post
anything to GitHub.

All GitHub operations (reading, searching, and updating Issues and Pull Requests) go through the GitHub CLI (`gh`). Do not use another GitHub client. If `gh` is unavailable or not authenticated, stop and report instead of falling back.

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

Normalize the first token of `$ARGUMENTS` into a plain number:

- `82`, `#82`, and a full Pull Request URL all mean Pull Request 82
- strip any leading `#` so the number is never interpolated as `##82`

Everything after that token is free-form finding text from the user.

If no number is given, resolve the Pull Request for the current branch
(`gh pr view --json number`). If that finds nothing, stop and report.

# 2. Collect the findings

Gather findings from these sources, in order:

1. the free-form text remaining in `$ARGUMENTS`
2. a `pr-review` result produced earlier in this same conversation
3. review state on GitHub:

```bash
gh pr view <N> --comments
```

For inline review comments, read them with a GET request only:

```bash
gh api repos/<owner>/<repo>/pulls/<N>/comments
```

Never use `gh api` with a method that writes.

If sources 1 and 2 are both empty and GitHub has no unresolved review findings, stop
and report that there is nothing to fix. Do not invent work.

List the collected findings before changing anything, so the set being acted on is
explicit.

# 3. Get onto the Pull Request branch

Determine the Pull Request's head branch (`gh pr view <N> --json headRefName`).

- Already on that branch, in a checkout that is not the default-branch checkout → continue there.
- Otherwise → work in an isolated worktree. Use the EnterWorktree tool with the name `pr-<N>`, then check the Pull Request out into it:

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
- Conventional Commits format with a concise Japanese subject
- no tool traces, no co-author trailers

Push to the existing remote branch. Do not force-push. Do not push to the default branch.

# 10. Report

Do not merge. Do not post to GitHub.

# Final response

Return:

- Pull Request number and URL
- findings fixed, each with what changed
- findings declined, each with the reason
- verification run and its result, including pre-existing failures
- the pushed branch and commits
- follow-up work that should become a separate Issue
