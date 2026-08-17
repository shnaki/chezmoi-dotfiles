---
name: issue-pr
description: "Implement exactly one GitHub Issue as exactly one focused Pull Request."
argument-hint: "[issue-number] [--merge]"
disable-model-invocation: true
---

Implement the GitHub Issue named in `$ARGUMENTS` as exactly one Pull Request.

The Issue defines the scope boundary.

# 0. Parse the arguments

Normalize the Issue number: `31`, `#31`, and a full Issue URL all mean Issue 31. Strip
any leading `#` so the number is never interpolated as `##31`. Use the normalized number
everywhere below, including in `Closes #<N>`.

`--merge` is an option, not an Issue number. Remove it before interpreting the rest.
With it, land the Pull Request after creating it (step 13). Without it, stop at Pull
Request creation.

Follow all repository-specific instructions in:

- CLAUDE.md
- applicable `.claude/rules/`
- project configuration
- existing repository conventions

# Core rules

- One Issue must produce exactly one Pull Request.
- Do not include unrelated changes.
- Do not silently expand the Issue scope.
- Prefer the smallest complete solution.
- Never weaken tests or validation merely to make the change pass.
- Never modify the default-branch checkout directly.
- Never merge the Pull Request, unless `--merge` was requested (step 13).
- Never force-push unless the repository explicitly requires it and the user has explicitly authorized it.
- All GitHub operations (reading, searching, and creating Issues and Pull Requests) go through the GitHub CLI (`gh`). Do not use another GitHub client. If `gh` is unavailable or not authenticated, stop and report instead of falling back.

# 1. Read the Issue

Read (`gh issue view <N> --comments`):

- the Issue title
- the full Issue body
- all relevant comments
- linked Issues or Pull Requests when relevant

Determine:

- the actual problem
- expected behavior
- acceptance criteria
- explicit scope
- explicit out-of-scope work

Do not begin editing before understanding the Issue.

# 2. Check for existing work

Check whether:

- a Pull Request already exists for this Issue (`gh pr list --search "<N>" --state all`)
- another branch appears to implement the same change
- the Issue has become obsolete
- the Issue depends on an unmerged change

Avoid duplicate implementation.

If another active Pull Request already implements the Issue, stop and report it unless the task explicitly requires replacing or continuing that work.

# 3. Inspect the implementation

Investigate the relevant code before deciding how to implement the change.

Inspect:

- current behavior
- surrounding architecture
- relevant tests
- similar existing implementations
- shared types or APIs
- generated files
- schema or migration implications
- repository-specific patterns

Prefer existing abstractions and conventions over introducing new ones.

# 4. Define the minimum implementation scope

Before editing, determine the minimum complete set of changes required to satisfy the Issue.

The Pull Request must not include unrelated:

- refactoring
- cleanup
- formatting
- renaming
- dependency upgrades
- architecture changes
- bug fixes
- feature additions

If unrelated problems are discovered, report them separately.

Do not fix them unless they are necessary to complete the current Issue.

# 5. Ensure isolation

Perform implementation in a dedicated branch and isolated worktree.

Determine where the session currently is:

- **Already in a dedicated worktree for this Issue** — a worker started by `ship-issues`,
  or a session resuming earlier work. Continue there.
- **In the repository's default-branch checkout** — create the isolated worktree with the
  EnterWorktree tool, using the name `<N>-<slug>` (`<slug>` is a short kebab-case
  description of the change).

Then, inside the worktree:

```bash
git fetch origin
```

Confirm the worktree's HEAD contains the current tip of the base branch
(`git merge-base --is-ancestor origin/<base> HEAD`). If it does not and the tree is
clean, `git reset --hard origin/<base>`.

Create the working branch `<N>-<slug>` and commit there. Never commit onto the branch
the worktree was created on: that branch is disposable and is cleaned up by the sweeper.

Do not edit files in the repository's default-branch checkout.

Keep this Issue isolated from other concurrent Issue implementations.

Do not call ExitWorktree when the work is done. Cleanup belongs to `pr-land` and
`worktree-sweep`, after the Pull Request has landed.

# 6. Implement

Implement the smallest complete solution that satisfies the Issue.

Follow repository conventions.

When appropriate:

- add regression tests for bugs
- add tests for new behavior
- update existing tests
- update documentation required by the change
- regenerate generated artifacts using the repository's normal tooling

Do not manually edit generated files when the repository provides a generator.

# 7. Verify incrementally

Run focused verification first.

Examples include:

- affected unit tests
- affected integration tests
- type checking for the affected package
- targeted linting

Then run the broader verification required by the repository instructions.

Do not invent generic verification commands when the repository already defines its own.

If verification fails:

1. determine whether the failure was caused by this change
2. fix failures caused by this change
3. do not modify unrelated code to repair pre-existing failures

Clearly document any relevant pre-existing failures.

# 8. Review the complete diff

Before committing, inspect the entire diff against the base branch.

Check specifically for:

- accidental unrelated changes
- unnecessary refactoring
- duplicated logic
- missing error handling
- compatibility regressions
- missing tests
- debugging code
- temporary files
- excessive comments
- accidental generated-file edits
- unexpected lock-file changes
- changes outside the Issue scope

Remove anything that does not belong in the Issue.

# 9. Confirm Issue completion

Re-read the Issue after implementation.

Verify every acceptance criterion against the actual change.

Do not assume that passing tests automatically means the Issue is complete.

# 10. Commit

Create a focused commit or small coherent set of commits according to repository conventions.

Do not include unrelated files.

Use the repository's normal commit-message conventions when available.

# 11. Push

Push the Issue branch to the configured remote.

Do not push directly to the default branch.

Do not force-push.

# 12. Create exactly one Pull Request

Create one Pull Request for Issue #<N> with `gh pr create`.

Use a concise title describing the completed change.

The Pull Request body should include:

## Summary

What changed.

## Why

Why the change was necessary.

## Verification

What was run or otherwise verified.

## Issue

Include:

Closes #<N>

Mention relevant known limitations or pre-existing failures when necessary.

Label the Pull Request from the labels the repository already has, following
`~/.claude/skills/label-apply/labeling-rules.md` (read it by path): the type label
that matches the commit type (`fix` → bug, `feat` → feature, …), or the type label
already on Issue #<N> when it has one. Pass it with `--label`. Never create a label;
if nothing in the repository fits, add none.

# 13. Land the Pull Request

Only with `--merge`. Without it, stop here and do not merge.

Follow the workflow in `~/.claude/skills/pr-land/SKILL.md`. Read it by path; `pr-land`
is `disable-model-invocation: true` and cannot be selected as a skill from here.

If `pr-land` stops (draft, conflict, failing checks, `CHANGES_REQUESTED`), report the
stop condition. Do not override it.

# Completion conditions

The task is complete only when:

- Issue #<N> has been addressed
- the implementation is limited to the Issue scope
- relevant verification has completed
- failures caused by the change have been fixed
- the complete diff has been reviewed
- the branch has been pushed
- exactly one Pull Request exists for the Issue
- the Pull Request references the Issue
- there are no unintended uncommitted changes
- with `--merge`: the Pull Request is merged, or the reason it is not is reported

# Final response

Return:

- Pull Request URL
- concise implementation summary
- verification performed
- any relevant pre-existing verification failures
- any follow-up work discovered but intentionally excluded
- with `--merge`: the merge result, and the cleanup `pr-land` performed
