# State file template

Template for the run file that `ship-issues` writes to
`~/.claude/ship-issues/<repo-name>-<YYYYMMDD-HHMM>.md` (`SKILL.md`, "Progress state").

`~/.claude/scripts/work-status.sh` reads this file. It depends on the exact shape below:

- the `- key: value` header lines right after the H1, one per line: it reads
  `repository`, `started`, `options`, and `requested issues`; `base` is for human
  readers (and `--resume`) and is not parsed. `options` is the run's option tokens as
  given, values included (`--worker-model opus`), so `--resume` can read them back
- one table whose data rows begin with `| #<N> |` — the Issue number is the first cell,
  and the branch name appears somewhere in the row
- a line that begins with `DONE` (or `**DONE**`) once the run has finished

`<repo-name>` in the file name is the GitHub repository name (the part after `/` in
`nameWithOwner`); `work-status.sh` matches a file to the repository by that prefix or by
the `- repository:` header, so a clone under another directory name still shows up.

Keep the keys, the column order, and the `DONE` marker exactly as they are. Add free
text only below the table (a `## Log` section), never between the header lines and the
table.

Every cell of the table has a value; use `-` for "none yet". Update the table in place
instead of appending a second table.

---

```markdown
# ship-issues: <repo-name> <YYYYMMDD-HHMM>

- repository: <owner/repo>
- started: <YYYY-MM-DD HH:MM>
- options: <--merge --dry-run --worker-model opus … | none>
- requested issues: #<N1> #<N2> …
- base: <base-branch>

## Issues

| # | title | class | wave | status | branch | worktree | agent | PR | merge | notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| #<N1> | <title> | ready | 1 | running | <N1>-<slug> | .claude/worktrees/<name> | <agent id or -> | - | - | - |
| #<N2> | <title> | ready | 2 | pending | - | - | - | - | - | after #<N1> |
| #<N3> | <title> | duplicate | - | skipped | - | - | - | - | - | same as #<M> |

## Waves

- Wave 1: #<N1>
- Wave 2: #<N2>, depends on #<N1>

## Log

- <HH:MM> wave 1 started
- <HH:MM> #<N1> worker finished: PR <url>

DONE
```

Column values:

- `class` — the step 3 classification: `ready` / `already implemented` / `in progress` /
  `blocked` / `obsolete` / `duplicate` / `needs investigation`.
- `wave` — the wave number from step 6, or `-` when no worker will run.
- `status` — how far the worker got: `pending` / `running` / `PR created` /
  `PR merged` / `PR created, not merged` / `failed` / `deferred`; or `skipped` for every
  Issue whose `class` is not `ready` (no worker runs for it). `running` is deliberately
  not `in progress`, which is a `class` value meaning "an open Pull Request already
  exists". The Completion status in the final report is derived from `class` and
  `status` together.
- `branch`, `worktree`, `agent` — what the worker was given (step 9 records them); fill
  `agent` with the Agent task id when it is known.
- `PR` — the Pull Request URL, or `-`.
- `merge` — `-`, `merged`, or the reason `pr-land` stopped (`--merge` only).
- `notes` — dependencies (`after #N`), the survivor of a duplicate, the failure class from
  step 13, or the reason a worker was not started.

Write `DONE` only after step 15 has finished. Under `--dry-run`, write it right after the
plan so `work-status` does not list the file as an unfinished run.
