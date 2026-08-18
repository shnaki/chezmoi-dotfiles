# State file template

Template for the run file that `ship-issues` writes to
`~/.claude/ship-issues/<repo-name>-<YYYYMMDD-HHMM>.md` (`SKILL.md`, "Progress state").

`~/.claude/scripts/work-status.sh` reads this file. It depends on the exact shape below:

- the five `- key: value` header lines, with these keys, one per line, at the start of
  the file
- one table whose data rows begin with `| #<N> |` — the Issue number is the first cell,
  and the branch name appears somewhere in the row
- a line that begins with `DONE` (or `**DONE**`) once the run has finished

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
- options: <--merge --dry-run … | none>
- requested issues: #<N1> #<N2> …
- base: <base-branch>

## Issues

| # | title | class | wave | status | branch | worktree | agent | PR | merge | notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| #<N1> | <title> | ready | 1 | in progress | <N1>-<slug> | .claude/worktrees/<name> | <agent id or -> | - | - | - |
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
- `status` — `pending` / `in progress` / `PR created` / `PR merged` /
  `PR created, not merged` / `failed` / `deferred` / `skipped`.
- `branch`, `worktree`, `agent` — what the worker was given; fill `agent` with the Agent
  task id when it is known.
- `PR` — the Pull Request URL, or `-`.
- `merge` — `-`, `merged`, or the reason `pr-land` stopped (`--merge` only).
- `notes` — dependencies (`after #N`), the survivor of a duplicate, the failure class from
  step 13, or the reason a worker was not started.

Write `DONE` only after step 15 has finished. Under `--dry-run`, write it right after the
plan so `work-status` does not list the file as an unfinished run.
