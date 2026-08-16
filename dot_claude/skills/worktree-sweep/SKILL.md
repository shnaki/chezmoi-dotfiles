---
name: worktree-sweep
description: "Remove leftover agent worktrees under .claude/worktrees/ and local branches that are already merged or whose upstream is gone."
argument-hint: "[--dry-run] [--recursive] [PATH...]"
disable-model-invocation: true
---

Sweep leftover git worktrees and stale local branches.

All decisions live in `~/.claude/scripts/worktree-sweep.sh`.

Do not reimplement its rules here, and do not delete worktrees or branches with
your own `git` commands.

# 1. Run the script

Pass `$ARGUMENTS` through unchanged:

```
sh ~/.claude/scripts/worktree-sweep.sh $ARGUMENTS
```

With no arguments it sweeps the current repository.

If the script is missing, report that and stop. Do not fall back to manual deletion.

# 2. Report the result

Summarize the script output:

- how many worktrees were removed and how many branches were deleted
- every item the script kept, together with the reason it reported

Never omit the kept items. They are the cases that need a human decision.

# 3. Follow up only when asked

The script intentionally keeps anything holding work that is not on a remote:

- worktrees with uncommitted changes
- worktrees whose HEAD is on no remote branch
- branches whose upstream is gone but that are not merged and have no merged Pull Request

It also keeps worktrees it cannot safely take:

- `locked by a running claude session (pid N)` — that session is still alive.
- `locked: <reason>` — a lock somebody set by hand, with no pid to check.
- `in use by another process` — a shell or session has the directory open, so
  neither git nor `rm` can delete it.

A lock whose pid is dead is stale; the script unlocks it itself and sweeps the
worktree in the same run. Under `--dry-run` that shows up as an `unlock` line
instead, and no lock is actually released.

Report these. Do not force-delete them, and do not re-run with `--force` to get
past them — `--force` only relaxes the guard for recently modified worktrees.
For a live lock or a busy directory, the fix is to close the owning session or
shell and run the script again, not `git worktree unlock` or `rm -rf`.

If the user asks to remove a kept item, confirm what would be lost before acting.
