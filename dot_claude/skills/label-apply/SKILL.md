---
name: label-apply
description: "Re-label existing Issues and Pull Requests using the labels the repository already has, following the shared labeling rules; never creates labels."
argument-hint: "[--dry-run] [--issues|--prs] [--all] [--limit N] [numbers-or-urls...]"
disable-model-invocation: true
---

Re-label the Issues and Pull Requests selected by `$ARGUMENTS`.

Invoking this skill is the authorization to change labels on the selected items. Do not
ask for confirmation again before applying, unless step 4 says so.

The rules for choosing labels live in `~/.claude/skills/label-apply/labeling-rules.md`.
Read that file first and follow it; do not paraphrase or extend it here.

All GitHub operations go through the GitHub CLI (`gh`). Do not use another GitHub
client. Before the first `gh` call, run `gh auth status`; if `gh` is unavailable or not
authenticated, stop and report instead of falling back.

# Core rules

- Never create, rename, or delete a label. Only labels that already exist may be applied.
- Never touch labels outside the categories the rules resolve (type / priority / status /
  flags). Unknown labels stay exactly as they are.
- Never edit titles, bodies, comments, assignees, milestones, or state, and never close
  or reopen anything.
- Prefer leaving an item undecided over guessing. Report every undecided item with the
  reason.

# 0. Parse the arguments

Options:

- `--dry-run` — build and print the plan, change nothing.
- `--issues` / `--prs` — restrict to Issues or Pull Requests. Default: both.
- `--all` — include closed items. Default: open only.
- `--limit N` — maximum items per kind to fetch. Default: 200.

Everything else is an item selector: `82`, `#82`, or a full Issue / Pull Request URL
all mean item 82. Strip the leading `#` so a number is never interpolated as `##82`.
When selectors are given, only those items are processed and `--all` is implied for
them.

# 1. Resolve the vocabulary

Follow step 1 of the rules: `gh label list --limit 500 --json name,description,color`
once, and resolve the type / priority / status / flag categories.

If no type-category label exists at all, stop and report. Suggest `/label-sync` to
install the default set first; do not create labels here.

# 2. Fetch the items

Without selectors:

```bash
gh issue list --state <open|all> --limit <N> --json number,title,body,labels,author,state,stateReason,url
gh pr list    --state <open|all> --limit <N> --json number,title,body,labels,author,state,isDraft,closingIssuesReferences,url
```

Skip `gh issue list` under `--prs` and `gh pr list` under `--issues`. With selectors,
use `gh issue view <N> --json ...` and `gh pr view <N> --json ...` for each; a number
that is a Pull Request fails under `gh issue view`, so try `gh pr view` when it does.

For a Pull Request whose title has no Conventional Commits prefix, also read the
commit headlines:

```bash
gh pr view <N> --json commits --jq '.commits[].messageHeadline'
```

Read comments (`gh issue view <N> --comments`, `gh pr view <N> --comments`) only when
the rules need them: status evidence (blocked / needs-info / duplicate / wontfix) or a
priority stated by a maintainer. Do not read every comment thread by default.

# 3. Decide and print the plan

Apply the rules to each item and produce a plan table before changing anything:

```
| # | kind | title | current (managed) | add | remove | reason |
```

- `current (managed)` lists only labels in the resolved categories; other labels are
  not shown and not touched.
- `reason` names the evidence (`title prefix feat`, `closes #12 (type/bug)`,
  `body: depends on #40 (open)`, …).
- Items with no change are not listed; report their count.
- Undecided items get their own list with the reason.

# 4. Apply

Under `--dry-run`, stop after the plan.

Otherwise apply the plan. Group Issues by identical (add, remove) pair and edit each
group in one call to keep permission prompts down:

```bash
gh issue edit <N1> <N2> ... --add-label "a,b" --remove-label "c"
gh pr edit <N> --add-label "a,b" --remove-label "c"
```

`gh pr edit` takes one Pull Request per call. Label names containing spaces are
quoted as shown.

If the plan removes a type label from more than 10 items, or the run would touch more
than 100 items, show the plan and ask once before applying. Otherwise do not ask.

If a `gh` call fails, record the error and continue with the remaining groups. Do not
retry with different labels to get past a failure.

# 5. Report

Return:

- counts: fetched, changed, unchanged, undecided, failed
- the applied changes (the plan table, with anything that failed marked)
- undecided items with reasons
- `gh` errors verbatim
- under `--dry-run`, say clearly that nothing was changed
