---
name: pr-describe
description: "Rewrite an existing Pull Request's description from its diff, commits, and linked Issue (Summary / Why / Verification / Issue, or the repository's template), keeping what a human wrote; optionally re-apply the type label. --dry-run shows the body without editing."
argument-hint: "[pr-number] [--dry-run]"
disable-model-invocation: true
---

Bring the description of the Pull Request identified by `$ARGUMENTS` back in line with
what the Pull Request actually contains. Use it after `pr-fix` has pushed more commits
than the body mentions, or on a Pull Request that was opened by hand with an empty or
stale body.

This skill edits the Pull Request body (and, when the rules ask for it, its type
label). It does not touch code, does not push, does not merge, and does not comment.

All forge operations go through the forge CLI: `gh` on GitHub, `glab` on GitLab. Before
the first such call, run `sh ~/.claude/scripts/forge-detect.sh`; it prints one line,
`<forge> <host> <path>`. On `github`, run the `gh` commands below as written. On `gitlab`,
read `~/.claude/forge/gitlab.md` once and run the `glab` equivalent it gives for each `gh`
command below, following its degrade rules where it lists none. If the script fails, stop
and report its message instead of falling back to another client.

# Core rules

- Describe what is there. Every claim in the body must be backed by the diff, the
  commits, or the check results; do not describe intent the code does not carry out,
  and do not invent verification that was not run.
- Keep what a human wrote. Checklists, reviewer notes, screenshots, `Closes #N` lines,
  and any section outside the ones this skill owns stay as they are, in place.
- Do not change the title. When it does not follow the repository's convention
  (Conventional Commits prefix, language), propose a title in the report and leave it.
- Labels come only from the labels the repository already has, following
  `~/.claude/skills/label-apply/labeling-rules.md` (read it by path). Never create a
  label. Only the type label is touched here.
- Write in the language the repository's Pull Requests use. No tool traces.
- Never edit a merged or closed Pull Request.

# 0. Parse the arguments

`--dry-run` is an option, not a Pull Request number. Remove it before interpreting the
rest. With it, print the proposed body and stop.

Normalize what remains into a plain number: `82`, `#82`, and a full Pull Request URL
all mean Pull Request 82. Strip any leading `#` so the number is never interpolated as
`##82`. If nothing remains, resolve the Pull Request for the current branch
(`gh pr view --json number`). If that finds nothing, stop and report.

# 1. Read the Pull Request

```bash
gh pr view <N> --json number,title,body,state,isDraft,baseRefName,headRefName,labels,commits,files,closingIssuesReferences,url
gh pr diff <N>
```

If `state` is not `OPEN`, stop and report.

Read the linked Issue(s) (`closingIssuesReferences`, and any `Closes #N` in the body)
with `gh issue view <M>`: the Issue's acceptance criteria are what the Summary should be
measured against.

Read the check results once for the Verification section, output rather than exit code
(`gh pr checks <N>`; `No checks reported` means there are none): name the checks that
passed and failed at the current head. Do not read logs; that is `ci-review`.

Read the repository's Pull Request template if it has one
(`.github/PULL_REQUEST_TEMPLATE.md`, `.github/pull_request_template.md`, or a
`PULL_REQUEST_TEMPLATE/` directory).

# 2. Understand the change

From the diff and the commit list, establish:

- what changed, per area (files, behavior, API, schema, generated artifacts)
- why, from the Issue and the commit bodies
- what verification the commits or the description mention, and what the checks say
- anything in the diff the current body does not mention, and anything the body claims
  that the diff no longer contains (typical after `pr-fix`)

# 3. Write the body

Structure: the repository's template when there is one; otherwise

```markdown
## Summary

What changed, in a few bullets or sentences. Behavior first, files second.

## Why

The problem being solved, from the Issue and the commits.

## Verification

What was run and its result, from the commits and the description; then the check
results at the current head (`checks: <passed> passed, <failed> failed`, or `no checks`).
Pre-existing failures are named as such only when a `ci-review` result in this
conversation says so.

## Issue

`Closes #<M>` for every linked Issue. Omit the section when there is none.
```

Merge, do not replace: keep every human-written line of the existing body that is
outside these sections, and inside them keep checklists and reviewer-facing notes.
Only prose that describes the change is rewritten. When the existing body already
matches the diff, say so and change nothing.

Type label: determine the type from the Pull Request title's Conventional Commits
prefix, else the commits, else the linked Issue's type label, following the rules file;
if the repository has a matching label and the Pull Request lacks it (or carries a
different type label), plan the change. When the vocabulary has no type labels, plan
none.

Print the proposed body and the label change. Under `--dry-run`, stop here and say
clearly that nothing was changed.

# 4. Apply

Write the body to a temporary file outside the repository (`mktemp`, or a file under
`$TMPDIR`) and edit:

```bash
gh pr edit <N> --body-file <file> [--add-label "<type>"] [--remove-label "<old type>"]
```

`gh pr edit` is a write and prompts for permission; that is expected. If it fails,
report the error verbatim and stop; do not retry with a different body.

# Final response

Return:

- Pull Request number and URL
- what the body now says that it did not, and what was removed as no longer true
- the label change, if any
- the proposed title, when the current one does not follow the convention (not applied)
- under `--dry-run`, that nothing was changed
