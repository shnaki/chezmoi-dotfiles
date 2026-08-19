---
name: ship-notes
description: "Turn notes into GitHub Issues and then orchestrate implementation of the created Issues as isolated Pull Requests."
argument-hint: "[--merge] [--ignore-checks] [--worker-model <alias>] [notes-file-or-text]"
disable-model-invocation: true
---

Process the notes in `$ARGUMENTS` from triage through Pull Request creation.

If `$ARGUMENTS` contains `--merge`, `--ignore-checks`, or `--worker-model <alias>`
(anywhere, not only at the start), remove those tokens — for `--worker-model` both the
flag and the alias after it — and treat the rest as the notes. All three are passed on
to the `ship-issues` phase unchanged: `--merge` lands each wave's Pull Requests instead
of stopping at Pull Request creation, `--ignore-checks` (only meaningful with `--merge`)
lets `pr-land` merge where GitHub Actions cannot run, and `--worker-model <alias>` runs
the implementation workers on that model (`opus` / `sonnet` / `haiku` / `fable`) while
the triage phase and the orchestrator keep the session's model.
`--dry-run` is not accepted here: run `/triage-notes --dry-run` to preview the Issues,
or `/ship-issues --dry-run` to preview the plan.

This skill has no logic of its own. It runs two other workflows back to back. Neither
can be selected as a skill from here (both are `disable-model-invocation: true`), so
read each by path and follow it as written:

- `~/.claude/skills/triage-notes/SKILL.md`
- `~/.claude/skills/ship-issues/SKILL.md`

All forge operations go through the forge CLI: `gh` on GitHub, `glab` on GitLab. Both
workflows start by running `sh ~/.claude/scripts/forge-detect.sh` and, on `gitlab`, read
`~/.claude/forge/gitlab.md`; follow that as they describe it. If the script fails, stop
and report its message instead of falling back to another client.

# Workflow

1. Triage the notes following `triage-notes` (read by path).
2. Create the resulting GitHub Issues.
3. Collect only the newly created actionable Issue numbers.
4. Process those Issues following `ship-issues` (read by path), passing `--merge`,
   `--ignore-checks`, and `--worker-model <alias>` through when they were given. `ship-issues` writes its state file
   as usual; an interrupted run is resumed with `/ship-issues --resume`, not with this
   skill.
5. Return the combined result.

# Boundaries

- Do not implement anything during the triage phase.
- Do not alter Issue boundaries after implementation begins merely to make the work easier.
- Do not include duplicate, obsolete, or non-actionable notes in the implementation phase.
- One Issue must result in at most one Pull Request.
- Do not merge Pull Requests unless `--merge` was given, and then only through the
  `ship-issues` phase.

# Final response

Return:

- created Issues
- notes that did not create Issues and why
- Pull Requests created for actionable Issues
- blocked or deferred Issues
- merge state of each Pull Request, when `--merge` was given
- execution waves and important dependencies
- the `ship-issues` state file path and, if the run did not finish, the exact
  `/ship-issues --resume` command
