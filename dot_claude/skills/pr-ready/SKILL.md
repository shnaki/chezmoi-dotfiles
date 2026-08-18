---
name: pr-ready
description: "Turn the work on the current branch into one Pull Request: review the diff, run verification, commit, push, and open the PR."
argument-hint: "[issue-number] [--merge]"
disable-model-invocation: true
---

Turn the work on the current branch into exactly one Pull Request.

# 0. Parse the arguments

`--merge` is an option, not an Issue number. Remove it before interpreting the rest.
With it, land the Pull Request after creating it (step 10). Without it, stop at Pull
Request creation.

What remains is an optional Issue number: `31`, `#31`, and a full Issue URL all mean
Issue 31. Strip any leading `#` so the number is never interpolated as `##31`. When
given, that Issue defines the scope boundary and the Pull Request closes it. When
omitted, infer the Issue from the branch and commits (see step 7); the Pull Request may
have no Issue at all.

Follow all repository-specific instructions in:

- CLAUDE.md
- applicable `.claude/rules/`
- project configuration
- existing repository conventions

# Core rules

- One branch produces exactly one Pull Request.
- Do not silently expand the scope of the work already on the branch.
- Do not add features, refactoring, or cleanup that the branch did not set out to do.
- Never weaken tests or validation merely to make the change pass.
- Never push to the default branch.
- Never force-push.
- Never merge the Pull Request, unless `--merge` was requested (step 10).
- All GitHub operations (reading, searching, and creating Issues and Pull Requests) go through the GitHub CLI (`gh`). Do not use another GitHub client. If `gh` is unavailable or not authenticated, stop and report instead of falling back.

# 1. Check the branch

Determine:

- the current branch
- the default branch of the repository
- the base branch the Pull Request should target (normally the default branch, unless the branch was clearly cut from another one)

If the current branch is the default branch:

- if the only work is uncommitted changes, create a new branch from the current position and continue there; the uncommitted changes carry over. Name it `<N>-<slug>` when an Issue number was given, otherwise `<slug>` — a short kebab-case description of the change, in the style of the repository's existing branch names
- if there are already commits on the default branch that are not on the remote, stop and report. Do not create the branch yourself; moving commits off the default branch is the user's decision.

# 2. Inspect the working tree and the diff

Run:

```bash
git status
git diff
git diff --staged
git log <base>..HEAD --oneline
git diff <base>...HEAD
```

Understand every change before proceeding: the uncommitted changes and the commits already on the branch. Do not review isolated snippets; read surrounding code when necessary.

# 3. Remove what does not belong

Check the complete diff for:

- changes unrelated to the purpose of the branch
- unnecessary refactoring, cleanup, formatting, or renaming
- debugging code and debug logging
- temporary files
- commented-out code
- excessive comments
- accidental generated-file changes
- unexpected lock-file changes
- secrets
- local environment paths or machine-specific configuration

Remove anything that does not belong. If a change cannot be removed cleanly, or its intent cannot be determined, do not guess: report it and stop.

# 4. Review the diff as a reviewer

Read the diff as an independent reviewer would, not as its author.

Look for concrete problems:

- incorrect behavior and edge cases
- incorrect error handling
- invalid assumptions
- state-management bugs and race conditions
- resource leaks and data-loss risks
- security or compatibility regressions
- violations of repository conventions
- missing tests for changed behavior, weakened assertions, disabled or skipped tests

Fix what is clearly a defect and within the scope of the branch. Do not demand tests mechanically when the repository or type of change does not warrant them. Whatever is found but intentionally left unfixed goes into the Pull Request body.

# 5. Verify

Find the verification the repository defines: CLAUDE.md, `.claude/rules/`, `package.json` scripts, `Makefile`, CI configuration, or similar.

Run focused verification first:

- affected unit and integration tests
- type checking for the affected package
- targeted linting

Then run the broader verification the repository requires.

Do not invent generic verification commands when the repository already defines its own. If the repository defines none, say so and do not fabricate results.

If verification fails:

1. determine whether the failure was caused by the change on this branch
2. fix failures caused by this change
3. do not modify unrelated code to repair pre-existing failures

Record pre-existing failures for the Pull Request body.

# 6. Commit uncommitted changes

If the working tree has uncommitted changes after steps 3–5, commit them following the `cm` skill workflow:

- group by logical theme; one theme, one commit
- stage files explicitly; never `git add -A` or `git add .`
- Conventional Commits format, with the subject in the language of the repository's
  existing commits (Japanese when the repository has no established convention)
- no tool traces, no co-author trailers

If the changes cannot be grouped confidently, ask before committing.

If there is nothing to commit and nothing on the branch beyond the base, stop and report; there is nothing to make a Pull Request from.

# 7. Resolve the Issue

If `$ARGUMENTS` names an Issue:

- read its title, body, and relevant comments (`gh issue view <N> --comments`)
- confirm that the work on the branch actually addresses it
- if the branch clearly does something else, report the mismatch and continue without `Closes`

If no Issue was given, look for candidates in:

- the branch name (`123-foo`, `issue-123`, `feat/123-foo`, `fix-123`)
- commit messages (`#123`, `Github-Issue:#123` trailers, `Closes #123`)

For each candidate, read the Issue and confirm that it exists and that its scope matches the branch. Use `Closes #N` only when the match is certain. When the match is plausible but not certain, do not close it; mention the candidate in the final response so the user can decide.

# 8. Push

Push the branch to the configured remote and set the upstream if it is not set.

Do not push to the default branch. Do not force-push.

# 9. Create exactly one Pull Request

First check whether a Pull Request already exists for this branch (`gh pr list --head <branch>`). If one exists, do not create another: report its URL and stop.

Create the Pull Request with `gh pr create`.

Title: concise, describing the completed change. Match the language and style of existing Pull Requests in the repository.

Body: if the repository has a Pull Request template, follow it. Otherwise use:

## Summary

What changed.

## Why

Why the change was necessary.

## Verification

What was run or otherwise verified, including pre-existing failures.

## Issue

`Closes #N` when an Issue was confirmed in step 7. Omit this section when there is no Issue.

Mention known limitations and anything found in step 4 but intentionally left unfixed.

Label the Pull Request from the labels the repository already has, following
`~/.claude/skills/label-apply/labeling-rules.md` (read it by path): the type label
that matches the commit type (`fix` → bug, `feat` → feature, …), or the type label
already on the Issue confirmed in step 7 when it has one. Pass it with `--label`.
Never create a label; if nothing in the repository fits, add none.

Without `--merge`, stop here. Do not merge the Pull Request.

# 10. Land the Pull Request

Only with `--merge`. Without it, this step does not run.

Follow the workflow in `~/.claude/skills/pr-land/SKILL.md`. Read it by path; `pr-land`
is `disable-model-invocation: true` and cannot be selected as a skill from here.

If `pr-land` stops (draft, conflict, failing checks, `CHANGES_REQUESTED`, `BLOCKED`),
report the stop condition. Do not override it.

# Completion conditions

The task is complete only when:

- the diff has been fully reviewed and unrelated changes have been removed
- the repository's verification has run, and failures caused by this branch have been fixed
- all intended changes are committed
- the branch has been pushed
- exactly one Pull Request exists for the branch
- there are no unintended uncommitted changes
- with `--merge`: the Pull Request is merged, or the reason it is not is reported

# Final response

Return:

- Pull Request URL
- concise summary of the change
- verification performed and its result
- pre-existing verification failures, if any
- changes removed from the diff, if any
- the Issue that was closed, or unconfirmed Issue candidates
- follow-up work discovered but intentionally excluded
- with `--merge`: the merge result, and the cleanup `pr-land` performed
