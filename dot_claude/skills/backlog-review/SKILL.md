---
name: backlog-review
description: "Survey a repository's open GitHub Issues and sort them into ready / blocked / duplicate / already implemented / obsolete / needs-info / needs investigation. Read-only: reports and suggests next commands, changes nothing on GitHub."
argument-hint: "[--limit N] [--label <name>] [--milestone <name>] [--since <YYYY-MM-DD>] [-R owner/repo] [numbers-or-urls...]"
disable-model-invocation: true
---

Survey the open Issues selected by `$ARGUMENTS` and sort each one into exactly one
class, so the user can see what is ready to implement, what is stuck, and what can be
closed.

This skill only reads. It is the step before `/ship-issues` (which implements the ready
ones) and `/label-apply` (which fixes labels). It hands numbers to those; it does not do
their work.

All GitHub operations go through the GitHub CLI (`gh`). Do not use another GitHub
client. If `gh` is unavailable or not authenticated, stop and report instead of falling
back.

# Core rules

- Read-only. Never run `gh issue edit`, `gh issue close`, `gh issue comment`,
  `gh issue pin`, `gh label`, or any other write. Do not create branches, worktrees, or
  commits, and do not implement anything.
- Do not use `gh api`, even for reads. Cross-references come from the Pull Request
  index (step 2) instead of the Issue timeline.
- Every Issue gets exactly one class. When the evidence does not decide, use
  `needs investigation` and say what is missing. Never promote an Issue to `ready` by
  guessing.
- Read the repository's code only as far as a class needs it (does the code already do
  this? does the code this Issue talks about still exist?). Do not estimate
  implementation impact, design changes, or plan waves; that is `ship-issues`.
- The definitions of blocked and needs-info are the ones in
  `~/.claude/skills/label-apply/labeling-rules.md`, step 4. Read that file by path when
  deciding those two classes; do not restate or extend it here.

# 0. Parse the arguments

Options:

- `--limit N` — maximum Issues to fetch. Default: 200.
- `--label <name>` — only Issues carrying this label. May repeat; repeats are ANDed
  (`gh issue list --label a --label b`).
- `--milestone <name>` — only Issues in this milestone.
- `--since <YYYY-MM-DD>` — only Issues updated on or after that date
  (`--search "updated:>=<date>"`).
- `-R owner/repo` — target another repository. Pass it to every `gh` call.

Everything else is an item selector: `82`, `#82`, or a full Issue URL all mean Issue
82. Strip the leading `#` so a number is never interpolated as `##82`. When selectors
are given, process only those Issues and ignore the filter options. A selected Issue
that is already closed is still read and classified; its `note` says `already closed`.

# 1. Fetch the Issues

Without selectors, one call:

```bash
gh issue list --state open --limit <N> [--label <name>]... [--milestone <name>] [--search "updated:>=<date>"] \
  --json number,title,body,labels,author,assignees,milestone,comments,createdAt,updatedAt,url
```

With selectors, one `gh issue view <N> --json <same fields>,state,stateReason` per
Issue. A number that turns out to be a Pull Request is reported as `not an Issue` and
skipped.

# 2. Fetch the Pull Request index

One call, not one per Issue:

```bash
gh pr list --state all --limit 300 \
  --json number,title,body,state,isDraft,mergedAt,headRefName,closingIssuesReferences,url
```

Match Pull Requests to Issues by, in order of strength:

1. `closingIssuesReferences`
2. `Closes #N` / `Fixes #N` / `Resolves #N` in the body
3. the `issue-pr` branch convention `<N>-<slug>` in `headRefName`
4. a plain `#N` in the title or body (weakest; mention it as `mentions #N` only)

# 3. Read each Issue

- Read the body from the fetched JSON.
- When `comments` is greater than zero, read the thread with
  `gh issue view <N> --comments`. Blocked, needs-info, and duplicate evidence usually
  lives there. Do not read threads with zero comments.
- Resolve `#N` references in the body and comments against the fetched Issues and the
  Pull Request index first. Only when a referenced number is in neither, run
  `gh issue view <N> --json number,title,state,stateReason,url` (falling back to
  `gh pr view` when it is a Pull Request).
- Look for duplicates in the fetched list by title and body similarity. When a title
  reads like something that may already exist outside the fetched set, run
  `gh search issues --repo <owner/repo> --state open "<keywords>"` at most once per
  Issue. Do not search for every Issue by default.
- Read code only when the class hinges on it: to confirm the code already does what
  the Issue asks, or that the code the Issue talks about is gone. If that cannot be
  settled in a few minutes of reading, classify as `needs investigation` and say so.

# 4. Classify

Apply the classes in this order; the first one whose evidence holds wins.

1. `already implemented` — a merged Pull Request references the Issue (step 2, strengths
   1–3) and the Issue was left open; or an open Pull Request references it (note
   `open PR #M`, plus `draft` when it is); or the code already satisfies the request.
2. `duplicate` — another **open** Issue tracks the same request. Name the survivor:
   by default the older one, or the one with the discussion and links, or the one a
   maintainer comment points to. The Issue being classified is the duplicate side.
3. `obsolete` — the code, feature, or dependency it targets no longer exists; the
   request was withdrawn in the thread; or a merged change made it moot without a
   closing reference.
4. `blocked` — per the rules file: the body, a comment, or a blocked-category label
   names a dependency (Issue, Pull Request, or external change) that is still open.
   When the named dependency is closed or merged, do not classify as blocked; classify
   by the remaining evidence and add `blocked label is stale` to the note.
5. `needs-info` — per the rules file: the last maintainer comment asks the reporter for
   something and no reply followed; or it is a question with no actionable request; or
   the body has no reproduction or expected behavior and the code cannot supply it.
6. `needs investigation` — none of the above can be decided from the evidence at hand.
   The note names what would decide it (`needs a repro on current main`, `unclear
   whether #40 covers it`, …).
7. `ready` — none of the above applies, the expected outcome is clear from the Issue,
   and there is no open dependency and no Pull Request.

Among ready Issues, when one clearly must land before another (the body says so, or
one introduces what the other consumes), note the order as `after #A`. Do not build
waves or inspect implementation footprint.

# 5. Report

Report in the conversation only. Do not write a file.

Open with the selection actually used (repository, filters or selectors, `--limit`) and
the counts: fetched, then one count per class.

Then one table per class, in the order of step 4, omitting empty classes:

```
| # | title | evidence | note |
```

`evidence` names the fact that decided the class, in a short fixed form:
`merged PR #12`, `open PR #15 (draft)`, `same as #7 (older)`, `depends on #40 (open)`,
`last comment asks reporter, no reply`, `code already handles this: <path>`,
`target removed in #33`. `note` carries the extras: `after #A`, `blocked label is
stale`, `already closed`, `not an Issue`.

Then a **Label mismatches** list: every Issue whose current status-category label
disagrees with its class (`status/blocked` but the dependency is closed; classified
duplicate or blocked with no such label; `status/needs-info` after the reporter
replied). Name the label and the class. Do not touch labels here.

Then **Suggested next commands**, as text the user can run, never executed by this
skill:

- `/ship-issues <numbers>` with the ready Issues in the order the notes suggest
- `/issue-refine <numbers>` with the needs investigation Issues
- `/label-apply <numbers>` with the Issues in the mismatch list
- one `gh issue close <N> --reason <completed|"not planned"> --comment "<why, naming
  the PR or the surviving Issue>"` line per already implemented, duplicate, and
  obsolete Issue, so the user can review and paste them

End with the sentence: `Nothing was changed on GitHub.`
