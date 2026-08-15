---
name: triage-notes
description: "Investigate bug and idea notes, determine appropriate issue boundaries, and create well-scoped GitHub Issues without implementing them."
argument-hint: "[notes-file-or-text]"
disable-model-invocation: true
---

Triage the notes provided in `$ARGUMENTS` and create appropriate GitHub Issues.

This skill is responsible for investigation and issue design only.

Do not implement any changes.
Do not create branches or Pull Requests.

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

Search existing open and recently closed GitHub Issues for duplicates or closely related work.

Also check open Pull Requests when relevant.

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

# 9. Create the Issues

Create the final Issues using GitHub CLI.

Do not invent labels, milestones, assignees, or projects unless repository conventions clearly require them.

After creation, record the Issue number and URL for each Issue.

# 10. Analyze dependencies

After all Issues are created, determine whether their implementations can safely run in parallel.

Consider both direct file overlap and semantic dependencies, including:

- shared APIs
- shared types
- database schemas
- migrations
- generated files
- central configuration
- dependency files
- producer/consumer relationships

Classify the Issues into execution waves when useful.

Example:

Wave 1:
- #101
- #102
- #104

Wave 2:
- #103, depends on #101

Do not change the Issues merely to make parallel execution easier.

# Completion

Return:

- created Issues with URLs
- notes that were merged into another Issue
- duplicates that were not created
- any notes that were not actionable
- proposed execution waves
- important dependency or conflict risks

Do not implement any Issue.
