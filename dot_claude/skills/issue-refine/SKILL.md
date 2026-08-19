---
name: issue-refine
description: "Investigate existing GitHub Issues against the repository and rewrite them to an implementable standard: concrete acceptance criteria, explicit scope, dependencies, and a split proposal when too large; never implements."
argument-hint: "[--dry-run] [--split] [issue-numbers-or-urls...]"
disable-model-invocation: true
---

Refine the GitHub Issues named in `$ARGUMENTS` so that an implementation worker
(`issue-pr`, or a `ship-issues` worker) can start from the Issue body alone.

Invoking this skill is the authorization to rewrite the body, title, and labels of the
selected Issues. Do not ask for confirmation again before applying (`--dry-run` is the
way to look first).

This skill is responsible for investigation and Issue design only. Do not implement
any changes. Do not create branches or Pull Requests.

All forge operations (reading, searching, editing, and creating Issues) go through the
forge CLI: `gh` on GitHub, `glab` on GitLab. Before the first such call, run
`sh ~/.claude/scripts/forge-detect.sh`; it prints one line, `<forge> <host> <path>`. On
`github`, run the `gh` commands below as written. On `gitlab`, read
`~/.claude/forge/gitlab.md` once and run the `glab` equivalent it gives for each `gh`
command below, following its degrade rules where it lists none. If the script fails, stop
and report its message instead of falling back to another client.

Follow all repository-specific instructions in:

- CLAUDE.md
- applicable `.claude/rules/`
- Issue templates and existing repository conventions

# Core rules

- Never lose information from the original Issue. Everything the reporter wrote is
  carried into the refined body, reworded only where it becomes clearer.
- Never change what the reporter asked for. Sharpen the request; do not replace it, and
  do not invent product requirements the Issue or the repository does not support.
- Never close or reopen an Issue, and never create an Issue except under `--split`.
- Never touch an Issue that was not selected.
- Labels come only from the labels the repository already has, following
  `~/.claude/skills/label-apply/labeling-rules.md` (read it by path; do not paraphrase
  it here). Never create a label.
- Write the Issue text in the language the repository's existing Issues use.
- Do not leave traces of the tools used to do the work in the Issue text.
- Prefer leaving an Issue unchanged over guessing. Report every unchanged Issue with the
  reason.

# 0. Parse the arguments

Options:

- `--dry-run` — investigate, print the plan and the proposed bodies, change nothing.
- `--split` — when an Issue is too large, create the child Issues (step 7) instead of
  only proposing them.

Everything else is an Issue selector: `31`, `#31`, and a full Issue URL all mean Issue
31. Strip any leading `#` so the number is never interpolated as `##31`. Accept any
mix of space- and comma-separated selectors and drop duplicates.

If no selector remains, stop and report. This skill never defaults to "all open
Issues".

Process each Issue independently. A failure on one Issue does not stop the others.

# 1. Read the Issue

For each Issue:

```bash
gh issue view <N> --json number,title,body,labels,state,stateReason,url,comments
```

Also read linked Issues and Pull Requests when the body or comments reference them.

Separate what the Issue already states clearly from what is missing or vague:

- the actual problem or user need
- the desired observable behavior
- acceptance criteria concrete enough to verify
- what is in scope and what is explicitly out of scope
- dependencies on other Issues, Pull Requests, or external changes
- decisions that only a human can make

Do not start rewriting before understanding the Issue.

# 2. Check existing work

For each Issue, check whether:

- a Pull Request already implements it. Look it up from the strongest signal down, the
  way `backlog-review` does:

  ```bash
  gh pr list --state all --limit 300 --json number,state,isDraft,headRefName,closingIssuesReferences,body
  ```

  A Pull Request belongs to Issue N when its `closingIssuesReferences` names N, else
  when its body says `Closes #N` (or `Fixes` / `Resolves`), else when its `headRefName`
  starts with `N-`. Do not use `gh pr list --search "<N>"`: a full-text search for `31`
  also matches `#310` and misses a Pull Request that only links the Issue through
  `closingIssuesReferences`
- another Issue tracks the same work (`gh issue list --search "<keywords>" --state all`)
- the Issue is closed, obsolete, or already resolved by a merged change
- the Issue depends on unresolved work

Give each Issue one verdict:

- refinable
- already implemented (a merged Pull Request, or the code, already covers it)
- in progress (an open Pull Request implements it; name it and whether it is a draft)
- duplicate (name the target)
- obsolete
- blocked (name the dependency; still refinable when the rest is clear)

Only `refinable`, `in progress`, and `blocked` Issues get a new body: an Issue with an
open Pull Request still benefits from clear acceptance criteria (the reviewer reads
them), but say in the report that a Pull Request exists so nobody starts a second
implementation. The others are reported with the evidence and left as they are: do not
close them, do not edit them, do not open replacements.

This skill is where `ship-issues` and `backlog-review` send an Issue they classified as
`needs investigation`; that classification is not a verdict here — investigate and give
it one of the verdicts above.

# 3. Investigate the repository

For each refinable Issue, inspect the relevant code before deciding what the Issue
should say.

Determine, when applicable:

- current behavior
- likely source of the problem
- affected modules
- relevant tests
- related APIs and shared types
- database / schema implications
- generated files
- configuration implications
- dependencies on other changes

For bugs, determine as much as possible: actual behavior, expected behavior, the
conditions that trigger it, the affected code path, regression risk. Do not claim
reproduction or root cause unless the evidence supports it; say what was checked and
what remains a hypothesis.

For ideas and feature requests, preserve the intended user value and do not
prescribe architecture. Use the implementation as evidence to clarify the boundary,
not to design the solution.

Do not refine an Issue solely by rewording it. If the investigation adds nothing the
Issue did not already say, leave it unchanged and report that.

# 4. Decide the size and the boundary

Ask, for the Issue as a whole:

1. Can this change be merged independently?
2. Does it provide independent user value or fix an independently observable defect?
3. Can it have clear acceptance criteria of its own?
4. Can it be verified independently?

If the answers are mostly yes and the work fits one focused implementation session,
keep the Issue as one unit.

If the Issue contains several independently mergeable or independently useful changes,
prepare a split proposal: for each child, a title, a one-line problem statement, and its
acceptance criteria. Do not split merely because the work touches different technical
layers, and do not create artificial micro-Issues that have no useful result on their
own.

# 5. Write the refined body

Use the structure below. Omit a section only when it would be empty; add the three
optional sections only when they carry information.

```markdown
## Problem
Explain the current limitation, defect, or user need.

## Expected behavior
Explain the desired observable behavior.

## Acceptance criteria
List concrete, verifiable conditions that define completion.

## Scope
Clarify what is included.

## Out of scope
Clarify obvious nearby work that should not be included.

## Dependencies                      (optional)
Open Issues / Pull Requests / external changes this depends on, with numbers.

## Open questions                    (optional)
Decisions only a human can make. Each question states what changes depending on
the answer.

## Split proposal                    (optional, step 4)
Proposed child Issues: title, problem, acceptance criteria.

## Investigation notes
Repository findings that help the implementer: where the behavior lives, relevant
tests, similar existing implementations, constraints found in the code.
```

Rules for the body:

- Carry over every fact, example, log excerpt, and link from the original body and the
  relevant comments. Where the reporter's wording is already precise, keep it.
- When the original text contradicts what the code shows, do not silently drop it:
  keep the reporter's claim and record the finding in Investigation notes.
- Investigation notes are informational, not mandatory implementation instructions.
  Do not commit the implementer to a specific file, class, library, or architectural
  approach unless that constraint is genuinely required.
- Keep the title unless it misstates the observable problem or capability. When it
  changes, keep it concise and report the change.
- Match the language and formatting of the repository's existing Issues.

# 6. Print the plan

Before changing anything, print one table for the run and, for each Issue that will
change, the full proposed body (and the new title when it changes):

```
| # | verdict | title (new title if changed) | labels add / remove | split |
```

`split` is `no`, `proposed`, or `create <count>` (under `--split`).

Under `--dry-run`, stop here and say clearly that nothing was changed.

# 7. Apply

For each Issue that will change, write the body to a temporary file outside the
repository (never inside the working tree; `mktemp` or a file under `$TMPDIR`) and edit
the Issue:

```bash
gh issue edit <N> --body-file <file>            # add --title "<new title>" only when it changed
```

Then set labels following the rules file:

- add exactly one type label when the Issue has none and the vocabulary has one that fits
- add the blocked status label when a named dependency is still open
- add needs-info only on the rules' own evidence (a maintainer question left unanswered).
  Open questions written by this skill are not that evidence; report them instead.
- never remove a label without the rules' evidence

```bash
gh issue edit <N> --add-label "a,b"                 # --remove-label "c" only with the rules' evidence
```

Under `--split`, for each Issue with a split proposal, create the child Issues first
so their numbers are known:

```bash
gh issue create --title "<title>" --body-file <file> --label "<type>"
```

Each child body uses the structure of step 5 and states `Part of #<N>` under Problem.
Then rewrite the parent so its Split proposal section becomes `## Split into` listing
the child numbers, and keep the parent's own Problem / Expected behavior as the
umbrella description. Do not close the parent.

If a `gh` call fails, record the error verbatim and continue with the remaining
Issues. Do not retry with a different body to get past a failure.

# Report

Return, per Issue:

- URL, verdict, and whether it was changed
- the sections that were added or materially changed, and the title change if any
- labels added / removed
- the split proposal, or under `--split` the created child Issues with URLs
- open questions that need a human answer

Then, for the run:

- dependencies between the selected Issues, as execution waves when useful:

  ```
  Wave 1: #101, #102
  Wave 2: #103, depends on #101
  ```

- Issues left unchanged, each with the reason
- `gh` errors verbatim
- under `--dry-run`, that nothing was changed

Do not implement any Issue.
