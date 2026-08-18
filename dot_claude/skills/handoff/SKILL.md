---
name: handoff
description: "Write a self-contained handoff document for the current work so another session or agent can continue it, or resume from an existing handoff."
argument-hint: "[--resume [file]] [note]"
disable-model-invocation: true
---

Hand the current work over to another session or another agent, or pick up work that was
handed over.

Interpret `$ARGUMENTS`:

- If it begins with `--resume`, remove that token. The rest, if any, is the handoff file
  to resume from (a path, or a bare file name under `~/.claude/handoff/`). When nothing
  follows, resume from the newest handoff for the current repository. Go to
  "Resuming" at the end of this file.
- Otherwise the whole of `$ARGUMENTS` is a free-text note: who or what the handoff is
  for, or extra instructions to record. It may be empty.

# Core rules

- Do not change the state of the repository. No commit, stash, checkout, reset, push,
  or file edits inside the repository. This skill records; it does not tidy up.
- Write for a reader who has none of this conversation: another session after a crash
  or context compaction, a worker started with the Agent tool in an isolated worktree,
  or a different tool entirely. The document is not a summary of the conversation; it is
  what that reader needs to start working within a minute.
- Separate what was verified (a command was run, a file was read) from what is assumed
  or remembered. Mark unknowns as unknown instead of guessing.
- Never write secrets, tokens, credentials, or the contents of environment variables
  into the document or the patch. If the diff itself contains such a value, say so in
  the document and do not write the patch.
- Do not name the tools or models used to do the work, in the document or in the patch.
- Use paths relative to the repository root. Record the absolute root path once, in
  Repository state, and nowhere else.
- All GitHub reads go through the GitHub CLI (`gh`). If `gh` is unavailable or not
  authenticated, do not stop: record the affected fields as unverified and continue.

# 1. Collect the repository state

Run, and keep the outputs for the document:

```bash
git rev-parse --show-toplevel
git rev-parse --abbrev-ref HEAD
git rev-parse HEAD
git status --short
git diff --stat HEAD
git stash list
git worktree list
```

Determine the base branch (normally the default branch, unless the branch was clearly
cut from another one) and run:

```bash
git log <base>..HEAD --oneline
```

Then, when `gh` is available:

```bash
gh pr list --head <branch> --state all
```

Look for an Issue number in the branch name (`123-foo`, `issue-123`, `fix/123-foo`),
in commit messages (`#123`, `Github-Issue:#123`, `Closes #123`), and in the conversation.
Confirm each candidate with `gh issue view <N>` and record only confirmed numbers as
the Issue; keep unconfirmed ones as candidates.

If the working tree is not a git repository, record that and go on with what the
conversation provides; the document is still useful.

# 2. Reconstruct the work from the conversation

Gather, from the conversation and from what was actually run:

- the original request, as close to verbatim as possible, and how its scope was
  settled since (what is in, what was explicitly put out)
- constraints and prohibitions the user stated during the work, verbatim
  ("do not touch X", "keep Y as is", "ask before Z")
- what is done, with the files and commits that carry it
- what is in progress: where the work stopped, in what state the touched files are,
  and what was about to happen next
- what has not been started
- decisions and their reasons, including alternatives that were considered and rejected
- verification that was run: the exact commands, their results, failures that were
  pre-existing, and verification that has not been run yet
- known problems and open questions, including questions the user has not answered
- if a plan file under `~/.claude/plans/` was in use, its path

If a mid-conversation message from the user changed direction, record the direction in
effect now, not the history.

# 3. Write the handoff file

Write to:

```
~/.claude/handoff/<repo-name>-<YYYYMMDD-HHMM>.md
```

`<repo-name>` is the repository directory name; `<YYYYMMDD-HHMM>` is the current time.
Create the directory if it does not exist. Never overwrite an existing handoff file; if
the name collides, append `-2`, `-3`, and so on.

If `git status --short` shows tracked changes (staged or unstaged), also write:

```
~/.claude/handoff/<repo-name>-<YYYYMMDD-HHMM>.patch
```

produced by `git diff HEAD --binary` (staged and unstaged together; `--binary` keeps
changes to binary files applicable). Untracked files are not in the patch: list them by path in the document so the reader knows they exist only in
this working tree. Skip the patch entirely if the diff contains a secret (see Core
rules) and say so.

The document uses these headings, in this order, in English. Write the prose in the
language the user has been using in the conversation. Leave a heading in place with
"None." rather than dropping it, so readers can rely on the shape.

```markdown
# Handoff: <repo-name> — <one-line goal>

## How to resume
In a session with this skill: `/handoff --resume <this file's path>`.
Otherwise: read this file, re-check Repository state against the actual repository
(branch, HEAD, uncommitted changes, Pull Request), apply the patch only if the working
tree is clean and HEAD matches, then work through Next steps from the top.

## Goal
The original request, and the scope as settled: in scope / out of scope.

## Constraints
What the user said must or must not be done, verbatim. None if none.

## Repository state
- Root: <absolute path>
- Branch: <branch> (base: <base>)
- HEAD: <sha> <subject>
- Commits ahead of base: <n> — list them
- Uncommitted changes: <n files> — see patch / None
- Untracked files: list / None
- Stashes: list / None
- Worktrees: list / None
- Pull Request: <url and state> / None / Unverified (gh unavailable)
- Issue: #<n> <title> / candidates: ... / None
- Patch file: <path> / None
- Plan file: <path> / None

## Done
What is finished, with the files and commits that carry it.

## In progress
Where the work stopped and in what state the touched files are.

## Next steps
1. One concrete step per line, in order, each with what "done" looks like.

## Decisions
- Decision — reason. Rejected: alternative — why.

## Verification
- Command — result (pass / fail / pre-existing failure). Not yet run: ...

## Known issues / open questions
Problems found and left, and questions the user has not answered.

## Key files
- path — why the reader needs it.
```

Next steps is the most important section. A reader should be able to start the first
step without reading the conversation. Prefer "run X, expect Y, then edit Z" over
"finish the feature".

# 4. Final response

Return:

- the path of the handoff file, and of the patch file if one was written
- one line stating the branch and whether uncommitted work exists only in this tree
- the first three Next steps
- the exact line to hand to the receiver: `/handoff --resume <path>` for a session with
  this skill, and `Read <path> and continue from "Next steps".` for anything else
- anything that could not be verified (for example because `gh` was unavailable)

Do not paste the whole document into the response; the file is the deliverable.

# Resuming

With `--resume`, locate the handoff file:

- a path or file name was given: use it (a bare name resolves under `~/.claude/handoff/`)
- nothing was given: pick the newest file in `~/.claude/handoff/` whose name starts with
  the current repository directory name

If no file is found, stop and report; do not invent a starting point.

Read the file. Do not trust it as fact. Re-establish the real state with the same
commands as step 1 and compare against Repository state. Report every difference before
doing anything else: new commits on the branch or on base, a branch or worktree that no
longer exists, a Pull Request that has been merged or closed, uncommitted changes that
are already present, an Issue that has been closed.

If a patch file is recorded:

- check that it exists, that the working tree is clean, and that HEAD matches the
  recorded HEAD
- if all three hold, run `git apply --check <patch>` and, when it passes, ask the user
  whether to apply it. Do not apply it unprompted.
- if any of them fails, report which and leave the patch alone; the user decides how to
  reconcile

Then give a short account of the reconciled state and continue with Next steps from the
first step that is not already done, honouring Constraints from the document. If the
note passed after `--resume` contains instructions, they take precedence over Next
steps.

When the resumed work itself needs to be handed over again, write a new handoff file.
Never edit the file that was resumed from.
