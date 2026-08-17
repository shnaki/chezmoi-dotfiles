---
name: label-sync
description: "Create or update the default GitHub label set on a repository (idempotent), renaming GitHub's default labels in place so existing Issues keep them."
argument-hint: "[--dry-run] [--prune] [-R owner/repo]"
disable-model-invocation: true
---

Bring a repository's labels in line with the default label set.

The label set and every decision live in `~/.claude/scripts/label-sync.sh`. Do not
reimplement its rules here, and do not create, rename, or delete labels with your own
`gh label` commands.

All GitHub operations go through the GitHub CLI (`gh`). If `gh` is unavailable or not
authenticated, stop and report instead of falling back.

# 1. Run the script

Pass `$ARGUMENTS` through unchanged:

```bash
sh ~/.claude/scripts/label-sync.sh $ARGUMENTS
```

With no arguments it targets the repository of the current directory and applies the
changes. `--dry-run` only reports. `--prune` additionally deletes labels outside the set
that no Issue or Pull Request carries; labels in use are never deleted.

If the script is missing, report that and stop. Do not fall back to manual `gh label`
commands.

# 2. Report the result

Summarize the script output, grouped by action:

- `create` — labels added
- `rename` — GitHub default labels (`bug`, `enhancement`, `documentation`, `question`,
  `duplicate`, `wontfix`, …) renamed into the set; Issues carrying them keep the label
- `update` — labels whose color or description was corrected
- `keep` — already correct (only the count)
- `unmanaged` — labels outside the set, left alone. Always list them by name
- `superseded` — a leftover label whose meaning is now covered by a set label (for
  example `ci` next to `type/chore`, or `bug` when `type/bug` already existed). Left
  alone; Issues still carry it. Always list these with the set label named by the script
- `delete` — only with `--prune`
- `failed` — every `gh` error, verbatim

A non-zero exit means at least one `gh` write failed. Report it plainly; do not retry
with different options to get past it.

# 3. Follow up only when asked

Do not resolve a `superseded` leftover yourself. Merging two labels means moving Issues
from one to the other, which is `label-apply`'s job
(`~/.claude/skills/label-apply/SKILL.md`), followed by deleting the empty label with
`--prune`. Suggest that sequence; run it only if the user asks.

When the run applied changes, mention that `/label-apply` will re-label existing Issues
and Pull Requests against the new set.
