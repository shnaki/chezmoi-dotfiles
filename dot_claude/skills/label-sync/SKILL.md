---
name: label-sync
description: "Create or update the default label set on a GitHub or GitLab repository (idempotent), renaming GitHub's default labels in place so existing Issues keep them."
argument-hint: "[--dry-run] [--prune] [--forge github|gitlab] [-R owner/repo]"
disable-model-invocation: true
---

Bring a repository's labels in line with the default label set.

The label set and every decision live in `~/.claude/scripts/label-sync.sh`. Do not
reimplement its rules here, and do not create, rename, or delete labels with your own
`gh label` or `glab label` commands.

All forge operations go through the forge CLI (`gh` on GitHub, `glab` on GitLab), inside
the script, which picks the CLI with `~/.claude/scripts/forge-detect.sh`. If it reports
that no CLI can answer, stop and report instead of falling back.

# 1. Run the script

Pass `$ARGUMENTS` through unchanged:

```bash
sh ~/.claude/scripts/label-sync.sh $ARGUMENTS
```

With no arguments it targets the repository of the current directory and applies the
changes. `--dry-run` only reports. `--prune` additionally deletes labels outside the set
that no Issue or Pull Request carries; labels in use are never deleted. `--forge` names
the forge explicitly; it is needed only with `-R` when the current directory is not a
repository on that forge.

If the script is missing, report that and stop. Do not fall back to manual `gh label` or
`glab label` commands.

# 2. Report the result

Summarize the script output, grouped by action:

- `create` — labels added
- `rename` — GitHub default labels (`bug`, `enhancement`, `documentation`, `question`,
  `duplicate`, `wontfix`, …) renamed into the set; Issues carrying them keep the label
- `update` — labels whose color or description was corrected
- `keep` — already correct (only the count). On GitLab, a label inherited from a group
  is also `keep` even when it differs, with a note: the project cannot edit it
- `unmanaged` — labels outside the set, left alone. Always list them by name
- `superseded` — a leftover label whose meaning is now covered by a set label (for
  example `ci` next to `type/chore`, or `bug` when `type/bug` already existed). Left
  alone; Issues still carry it. Always list these with the set label named by the script
- `delete` — only with `--prune`
- `retain` — only with `--prune`: an unmanaged or superseded label that was not deleted
  because it is still in use, because the CLI could not answer whether it is (offline,
  rate limit), or because it is a GitLab group label. List these by name with the
  reason; they count as `unmanaged` / `superseded`, not as `keep`
- `failed` — every CLI error, verbatim

A non-zero exit means at least one write failed. Report it plainly; do not retry with
different options to get past it.

# 3. Follow up only when asked

Do not resolve a `superseded` leftover yourself. Merging two labels means moving Issues
from one to the other, which is `label-apply`'s job
(`~/.claude/skills/label-apply/SKILL.md`), followed by deleting the empty label with
`--prune`. Suggest that sequence; run it only if the user asks.

When the run applied changes, mention that `/label-apply` will re-label existing Issues
and Pull Requests against the new set.
