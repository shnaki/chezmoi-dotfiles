---
name: issue-pr
description: "Implement exactly one GitHub Issue as exactly one focused Pull Request."
argument-hint: "[issue-number]"
disable-model-invocation: true
---

Implement GitHub Issue #$ARGUMENTS as exactly one Pull Request.

The Issue defines the scope boundary.

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
- Never merge the Pull Request.
- Never force-push unless the repository explicitly requires it and the user has explicitly authorized it.
- All GitHub operations (reading, searching, and creating Issues and Pull Requests) go through the GitHub CLI (`gh`). Do not use another GitHub client. If `gh` is unavailable or not authenticated, stop and report instead of falling back.

# 1. Read the Issue

Read (`gh issue view $ARGUMENTS --comments`):

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

- a Pull Request already exists for this Issue (`gh pr list --search "$ARGUMENTS" --state all`)
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

If the current session is already operating in the dedicated Issue worktree, continue there.

Do not edit files in the repository's default-branch checkout.

Keep this Issue isolated from other concurrent Issue implementations.

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

Create one Pull Request for Issue #$ARGUMENTS with `gh pr create`.

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

Closes #$ARGUMENTS

Mention relevant known limitations or pre-existing failures when necessary.

Do not merge the Pull Request.

# Completion conditions

The task is complete only when:

- Issue #$ARGUMENTS has been addressed
- the implementation is limited to the Issue scope
- relevant verification has completed
- failures caused by the change have been fixed
- the complete diff has been reviewed
- the branch has been pushed
- exactly one Pull Request exists for the Issue
- the Pull Request references the Issue
- there are no unintended uncommitted changes

# Final response

Return:

- Pull Request URL
- concise implementation summary
- verification performed
- any relevant pre-existing verification failures
- any follow-up work discovered but intentionally excluded
