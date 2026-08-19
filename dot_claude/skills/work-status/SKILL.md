---
name: work-status
description: "Show what is in flight in the current repository — open Pull Requests, agent worktrees and branches, unfinished ship-issues runs — with the next command for each row. Read-only."
argument-hint: "[--no-fetch] [PATH]"
disable-model-invocation: true
---

Report what is in flight and what to run next. Read-only.

All decisions live in `~/.claude/scripts/work-status.sh`. Do not reimplement its rules,
do not derive a different `next` yourself, and do not run the commands it suggests.
This skill changes nothing: no `gh` / `glab` writes, no sweep, no edits to state files.

All forge reads go through the forge CLI (`gh` on GitHub, `glab` on GitLab), inside the
script, which picks the CLI with `~/.claude/scripts/forge-detect.sh`. If the `forge`
column of the `repo` record is `no-remote` or `failed`, present the local-only result
and say so (the notes carry the reason). Do not fill the gap with another client.

# 1. Run the script

Pass `$ARGUMENTS` through unchanged:

```
sh ~/.claude/scripts/work-status.sh $ARGUMENTS
```

With no arguments it targets the repository of the current directory; running from
inside an agent worktree is fine. `PATH` targets another checkout. `--no-fetch` skips
`git fetch --prune`.

If the script is missing, report that and stop.

# 2. Render the result

The output is tab-separated; column 1 is the record type, and a `# ` line names the
columns before each type. Turn it into:

- **Header** — from the `repo` record: repository, base, where it was invoked from
  (`main` or `worktree:<name>`), the `fetch` state, and the `forge` column (`github`,
  `gitlab`, `no-remote`, or `failed`).
- **In flight** — one markdown table from the `row` records with the columns
  Issue | PR | checks | review | branch | worktree | agent | state | next | reason.
  `checks` (`pass` / `fail` / `pending` / `none` / `?`) and `review` are the facts the
  `next` column was decided from; keep them so the reader can see why. `none` means the
  Pull Request has no checks at all (CI disabled or no workflows / pipeline), which is normal
  and never a reason to wait. Keep `next` verbatim. Order: rows whose `next` is a skill
  command other than `/worktree-sweep` first, then `wait`, then `/worktree-sweep`, then
  `-` (done). Omit the table when there are no rows.
- **Unfinished ship-issues runs** — one entry per `state` record: file, started,
  options, requested issues, repository, resolved/total. Add one line of progress read
  from that file's `srow` records (the raw table rows) or, if they are not enough, from
  the file itself. Label it as what the file claims. The table above is what git and
  the forge actually show; when they disagree, the table wins.
- **Notes** — every `note` record, verbatim.
- The `summary` record as the last line.

`/pr-ready (in <worktree>)` means: run `/pr-ready` in that worktree, not from the main
checkout. `/pr-ready (on <branch>)` means: check that branch out first.

# 3. State the limits

Always end with this, in the user's language:

- Agent liveness is a heuristic. A worktree lock whose pid is alive is the only hard
  signal; a recently modified worktree, an existing branch, an open PR, and a state
  file entry are hints.
- Background Agent tasks are visible only in the session that started them. A run
  driven by another session shows up here only through its worktree, branch, and PR.
- A review left by `pr-review --post` is a comment, not a review decision, so a Pull
  Request keeps showing `/pr-review N` after it. Read the comments before reviewing
  again.
- Forge state is as of this run. Nothing was modified.

# 4. Do not act

Do not run `/pr-fix`, `/ci-review`, `/pr-review`, `/pr-land`, `/ship-issues --resume`,
`/pr-ready`, or the sweeper from here. Suggest; the user invokes them. If asked to "just do it",
name the skill to invoke instead of doing the work in this context.
