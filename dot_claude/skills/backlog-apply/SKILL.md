---
name: backlog-apply
description: "Carry out the results of a backlog-review from this conversation: close duplicate / obsolete / already-implemented Issues with a reason, ask the reporter on needs-info Issues, and set status labels. Never classifies on its own; --dry-run shows the plan."
argument-hint: "[--dry-run] [issue-numbers-or-urls...]"
disable-model-invocation: true
---

Apply the classification that `backlog-review` produced earlier in this conversation to
GitHub: close what it called duplicate, obsolete, or already implemented; ask the
reporter what it called needs-info; label what it called blocked. This is the write half
of `backlog-review`, which itself changes nothing.

Invoking this skill is the authorization to close and comment. Do not ask for
confirmation again before applying, except in the one case step 4 names (`--dry-run` is
the way to look first).

All GitHub operations go through the GitHub CLI (`gh`). Do not use another GitHub
client. Before the first `gh` call, run `gh auth status`; if `gh` is unavailable or not
authenticated, stop and report instead of falling back.

# Core rules

- Never classify. The classes come from a `backlog-review` result in this same
  conversation. Without one, stop and say to run `/backlog-review` first. Do not
  re-derive a class from the Issue, and do not act on a class the review did not give.
- Act on these classes only: `already implemented`, `duplicate`, `obsolete`,
  `needs-info`, `blocked`. Never touch `ready`, `in progress` (its Pull Request closes
  it), or `needs investigation` (that is `/issue-refine`).
- Never touch an Issue that was not in the review, or that the selectors exclude.
- Re-read every Issue before acting on it (step 2). The review may be minutes or hours
  old; an Issue that closed, changed, or gained a Pull Request since then is left alone
  and reported.
- Labels come only from the labels the repository already has, following
  `~/.claude/skills/label-apply/labeling-rules.md` (read it by path). Never create a
  label. Only status labels are touched here (`status/*`, or the repository's `blocked`
  / `needs-info` / `duplicate` / `wontfix` equivalents); type and priority are
  `label-apply`'s job.
- Comments and close reasons name their evidence (the Pull Request, the surviving
  Issue, the question) and nothing else. No tool traces. Write them in the language the
  repository's Issues use.
- Do not implement, edit Issue bodies, or reopen anything.

# 0. Parse the arguments

`--dry-run` — do everything up to the plan (step 3), change nothing.

Everything else is an Issue selector: `82`, `#82`, or a full Issue URL all mean Issue
82. Strip the leading `#` so a number is never interpolated as `##82`. With selectors,
act only on those Issues (they still need a class from the review); without, act on
every actionable Issue the review classified.

# 1. Take the classification from the conversation

Find the most recent `backlog-review` result in this conversation and take, per Issue:
its class, its evidence (the Pull Request number, the surviving Issue, the unanswered
question, the open dependency), and its note. If there is none, stop and report.

Keep only the actionable classes listed in Core rules. Report the rest as skipped, with
the class, so the user sees the whole review was considered.

# 2. Re-read each Issue

```bash
gh issue view <N> --json number,title,state,labels,url,comments,updatedAt
```

Skip and report the Issue when:

- it is no longer open
- it was updated after the review and the update changes the picture (a new comment
  from the reporter on a needs-info Issue, a new Pull Request reference, a label
  someone set by hand)
- the evidence no longer holds: the surviving Issue of a duplicate is closed, the merged
  Pull Request of an already-implemented Issue was reverted, the dependency of a
  blocked Issue is closed

For `already implemented`, confirm the Pull Request is merged
(`gh pr view <M> --json state,mergedAt`), not just closed. For `duplicate`, confirm the
surviving Issue is open (or itself closed as completed).

Resolve the repository's label vocabulary once (`gh label list --limit 500 --json name`)
and map, through the rules file, the status labels this skill may set: blocked,
needs-info, duplicate, wontfix (for obsolete). A category the repository has no label
for is simply not labelled; say so.

# 3. Plan

Print one table before changing anything:

```
| # | class | action | comment | labels |
```

Actions, by class:

- `already implemented` → `close --reason completed`, comment
  `Implemented by #<M> (merged <date>).`
- `duplicate` → `close --reason "not planned"`, comment `Duplicate of #<K>.`; add the
  duplicate status label when the vocabulary has one
- `obsolete` → `close --reason "not planned"`, comment stating the review's evidence
  (`The <target> this Issue describes was removed in #<M>.`); add the wontfix status
  label when the vocabulary has one
- `needs-info` → stay open; comment with the concrete question(s) the review found
  unanswered, addressed to the reporter (`@<login>`); add the needs-info status label
- `blocked` → stay open; add the blocked status label; comment
  `Blocked by #<D>.` only when the body or an existing comment does not already say so

Comment texts are one to three sentences. Under `--dry-run`, stop here and say clearly
that nothing was changed.

# 4. Apply

For each planned Issue, in the table's order. Write comment bodies to a temporary file
outside the repository (`mktemp`, or a file under `$TMPDIR`) and pass `--body-file`;
for the short close comments `--comment "<text>"` is fine.

```bash
gh issue close <N> --reason completed --comment "<text>"
gh issue close <N> --reason "not planned" --comment "<text>"
gh issue comment <N> --body-file <file>
gh issue edit <N> --add-label "<label>"
```

Ask once before continuing when the plan closes more than 10 Issues; otherwise do not
ask. Every `gh` write prompts for permission on its own (none of them is in the
allow-list); that is expected.

If a `gh` call fails, record the error verbatim and continue with the remaining Issues.
Do not retry with a different reason or body to get past it.

# Final response

Return:

- per Issue acted on: number, class, what was done (closed with reason / commented /
  labelled), URL
- Issues skipped, each with the reason (class not actionable, changed since the review,
  evidence no longer holds, `gh` error verbatim)
- Issues from the review that the selectors excluded, as a count
- under `--dry-run`, that nothing was changed

Then the sentence: `Nothing else was changed on GitHub.`
