---
name: triage-notes
description: "Investigate bug and idea notes, determine appropriate issue boundaries, and create well-scoped GitHub Issues without implementing them."
argument-hint: "[--dry-run] [notes-file-or-text]"
disable-model-invocation: true
---

Triage the notes provided in `$ARGUMENTS` and create appropriate GitHub Issues.

If `$ARGUMENTS` contains `--dry-run`, remove that token and treat the rest as the
notes. Under `--dry-run`, do everything up to and including the plan in step 10, print
the plan and every proposed Issue body, and stop without creating anything.

This skill is responsible for investigation and issue design only.

Do not implement any changes.
Do not create branches or Pull Requests.

All GitHub operations (reading, searching, and creating Issues and Pull Requests) go through the GitHub CLI (`gh`). Do not use another GitHub client. Before the first `gh` call, run `gh auth status`; if `gh` is unavailable or not authenticated, stop and report instead of falling back.

Write the Issue text in the language the repository's existing Issues use, and do not
leave traces of the tools used to do the work in it.

# Goals

Transform informal bug reports, ideas, TODOs, or rough notes into GitHub Issues that are:

- independently understandable
- independently mergeable where possible
- small enough for one implementation session
- explicit about expected behavior
- free from unnecessary implementation commitments
- non-duplicative with existing Issues

# 1. Read the notes

Read all notes before creating any Issues.

A note may become:

- one Issue
- multiple independent Issues
- part of another Issue
- no Issue because it is already tracked
- no Issue because investigation shows no actionable change

Do not assume that one note equals one Issue.

# 2. Investigate the repository

For each note, inspect the relevant codebase before deciding the Issue boundary.

Determine, when applicable:

- current behavior
- likely source of the problem
- affected modules
- relevant tests
- related APIs
- shared types
- database/schema implications
- generated files
- configuration implications
- dependencies on other changes

Do not create an Issue solely by rewriting the user's note.

Use the implementation as evidence to clarify what the actual problem or feature boundary is.

# 3. Check existing work

Search existing open and recently closed GitHub Issues for duplicates or closely related work (`gh issue list --search "<keywords>" --state all`).

Also check open Pull Requests when relevant (`gh pr list --search "<keywords>"`).

If the work is already tracked:

- do not create a duplicate Issue
- report the existing Issue or Pull Request instead

If the new note materially extends existing work, decide whether it belongs in the existing Issue or should become a separate independently mergeable Issue.

# 4. Determine Issue boundaries

Prefer one Issue per independently mergeable behavior change.

Use the following questions:

1. Can this change be merged independently?
2. Does it provide independent user value or fix an independently observable defect?
3. Can it have clear acceptance criteria of its own?
4. Can it be verified independently?

If the answers are mostly yes, prefer a separate Issue.

Do not split work merely because it touches different technical layers.

For example, a single feature may legitimately include:

- database changes
- backend changes
- API changes
- frontend changes
- tests

when all of them are required for one coherent behavior change.

Likewise, two changes may belong in separate Issues even when they modify the same file.

# 5. Keep Issues appropriately sized

Prefer Issues that can reasonably be completed by one coding-agent worker in one focused implementation session.

Prefer:

- one primary objective
- a small number of clear acceptance criteria
- minimal unrelated scope

If an Issue contains multiple independently useful or independently mergeable changes, split it.

Do not create artificial micro-Issues that have no useful result on their own.

# 6. Handle bugs

For bugs, determine as much as possible:

- actual behavior
- expected behavior
- conditions that trigger the bug
- affected code path
- regression risk

Do not claim reproduction or root cause unless supported by evidence.

# 7. Handle ideas and feature requests

For ideas, preserve the intended user value without inventing unnecessary product requirements.

Do not prematurely prescribe architecture.

For example, do not turn:

"Allow exporting search results as CSV"

into unrelated requirements such as:

- background job processing
- export history
- persistent storage
- notifications

unless the repository or the note provides evidence that they are required.

# 8. Write each Issue

Use a concise title describing the observable problem or desired capability.

Use the following structure when applicable:

## Problem

Explain the current limitation, defect, or user need.

## Expected behavior

Explain the desired observable behavior.

## Acceptance criteria

List concrete conditions that define completion.

## Scope

Clarify what is included when useful.

## Out of scope

Clarify obvious nearby work that should not be included when useful.

## Investigation notes

Record useful repository findings.

Investigation notes are informational, not mandatory implementation instructions.

Avoid committing the implementation worker to a specific file, class, library, or architectural approach unless that constraint is genuinely required.

# 9. Analyze dependencies

Before creating anything, determine whether the planned Issues can safely be
implemented in parallel, so the plan below can show it and `--dry-run` sees the same
result as a real run.

Consider both direct file overlap and semantic dependencies, including:

- shared APIs
- shared types
- database schemas
- migrations
- generated files
- central configuration
- dependency files
- producer/consumer relationships

Classify the Issues into execution waves when useful, referring to them by their row
in the plan (they have no number yet):

Wave 1:
- row 1
- row 2
- row 4

Wave 2:
- row 3, depends on row 1

Do not change the Issues merely to make parallel execution easier.

# 10. Create the Issues

Before creating anything, print the plan: one table for the run and, below it, the full
proposed body of every Issue.

```
| row | title | labels | from note(s) | depends on |
```

Under `--dry-run`, stop here and say clearly that nothing was created.

Otherwise, for each Issue, write the body to a temporary file outside the repository
(never inside the working tree; `mktemp` or a file under `$TMPDIR`) and create it:

```bash
gh issue create --title "<title>" --body-file <file> --label "<labels>"
```

Label each Issue from the labels the repository already has, following
`~/.claude/skills/label-apply/labeling-rules.md` (read it by path). Pass them with
`--label`. Never create a label; if nothing in the repository fits, add none and say so
in the report.

Do not invent milestones, assignees, or projects unless repository conventions clearly require them.

If a `gh` call fails, record the error verbatim and continue with the remaining Issues.
Do not retry with a different body to get past a failure.

After creation, record the Issue number and URL for each Issue, and restate the waves
from step 9 with the real numbers (`Wave 2: #103, depends on #101`).

# Completion

Return:

- created Issues with URLs
- notes that were merged into another Issue
- duplicates that were not created
- any notes that were not actionable
- proposed execution waves (by row under `--dry-run`, by Issue number otherwise)
- important dependency or conflict risks
- `gh` errors verbatim
- under `--dry-run`, that nothing was created

Do not implement any Issue.
