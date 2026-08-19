---
name: repo-bootstrap
description: "Set a repository up for the other skills: install the default label set, add Pull Request and Issue templates that match what the skills write, and a CLAUDE.md skeleton — creating only what is missing. --dry-run shows the plan; branch protection and Actions settings are reported for a human."
argument-hint: "[--dry-run] [-R owner/repo]"
disable-model-invocation: true
---

Prepare a repository so that `triage-notes`, `issue-pr`, `pr-ready`, `pr-land`, and the
label skills find what they expect: a label vocabulary, templates whose sections match
the bodies those skills write, and a place for repository instructions.

Invoking this skill is the authorization to run `label-sync` and to add files. It never
overwrites a file that exists, and it never changes repository settings on GitHub.

All forge operations go through the forge CLI: `gh` on GitHub, `glab` on GitLab. Before
the first such call, run `sh ~/.claude/scripts/forge-detect.sh`; it prints one line,
`<forge> <host> <path>`. On `github`, run the `gh` commands below as written. On `gitlab`,
read `~/.claude/forge/gitlab.md` once and run the `glab` equivalent it gives for each `gh`
command below, following its degrade rules where it lists none. If the script fails, stop
and report its message instead of falling back to another client.

# Core rules

- Create only what is missing. An existing `CLAUDE.md`, template, or `.gitignore` is
  read and left alone; say what it already covers.
- Local files are committed on the current branch following the `cm` skill workflow,
  in one commit, and not pushed. Opening the Pull Request is `/pr-ready`.
- Never edit repository settings (branch protection, Actions permissions, merge
  methods): those need `gh api` / `glab api` writes or the web UI. Report what to set
  and where.
- Labels go through `~/.claude/scripts/label-sync.sh`; do not run `gh label` or
  `glab label` here.
- Templates are written in the language the repository's Issues and Pull Requests use
  (English when the repository has none yet and no other convention). No tool traces.

# 0. Parse the arguments

- `--dry-run` — investigate, print the plan, change nothing (pass `--dry-run` on to
  `label-sync.sh` too).
- `-R owner/repo` — target another repository. Pass it to every `gh` call and to
  `label-sync.sh`. Local files can only be written when a checkout of that repository
  is the current directory; otherwise plan them and say they were skipped.

Anything else is an error: stop and report.

# 1. Look at the repository

```bash
gh repo view --json nameWithOwner,defaultBranchRef,visibility,isPrivate,hasIssuesEnabled,squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed,deleteBranchOnMerge
gh workflow list
gh label list --limit 500 --json name
git status --short
```

And on disk: `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, `.github/PULL_REQUEST_TEMPLATE.md`
(or `pull_request_template.md`, or the `PULL_REQUEST_TEMPLATE/` directory),
`.github/ISSUE_TEMPLATE/`, `.gitignore`, and enough of the tree to name the language and
build tool (`package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`, `Makefile`, …).
On GitLab the template paths are `.gitlab/merge_request_templates/Default.md` and
`.gitlab/issue_templates/{bug,feature}.md` (with no `labels:` front matter — GitLab
templates carry no front matter; add a `/label ~"<label>"` quick action line at the
end instead), and "Actions" means the pipeline; read every `.github/...` path in this
skill that way.

Stop and report when the working tree is dirty: the bootstrap commit must contain only
what this skill adds.

# 2. Plan

Print what will happen, one line per item, before doing anything:

- **labels** — the `label-sync.sh --dry-run` output (create / rename / update / keep)
- **`.github/PULL_REQUEST_TEMPLATE.md`** — create with the sections `pr-ready` /
  `issue-pr` write (`## Summary`, `## Why`, `## Verification`, `## Issue` with a
  `Closes #` hint), or "exists, kept"
- **`.github/ISSUE_TEMPLATE/bug.md`** and **`feature.md`** — create with the sections
  `triage-notes` writes (`## Problem`, `## Expected behavior`, `## Acceptance criteria`,
  `## Scope`, `## Out of scope`, `## Investigation notes`), each with a one-line hint of
  what goes there and a `labels:` front matter naming the repository's type label when
  the vocabulary has one (`type/bug` / `type/feature`, or `bug` / `enhancement`), or
  "exists, kept"
- **`CLAUDE.md`** — create a skeleton with these headings and one placeholder line each,
  or "exists, kept": `# Language` (of code comments, commits, Issues, Pull Requests),
  `# Verification` (the commands to run before a Pull Request; fill from what step 1
  found — `npm test`, `go test ./...`, `make check` — or leave `TODO`), `# Branches`
  (default branch, whether squash merging is the convention, from step 1)
- **`.gitignore`** — "exists, kept" or "missing: add one for <language> by hand"
  (GitHub's templates need `gh api`; do not fetch them here)
- **settings a human sets on the forge** — one line each, only when relevant: enable
  "Automatically delete head branches" when `deleteBranchOnMerge` is false (`pr-land`
  deletes explicitly, but the setting removes the race); allow squash merging when it
  is off and the convention wants it; branch protection with required review if more
  than one person merges; for a private repository, that GitHub Actions minutes are
  metered and the skills treat a billing failure as `infrastructure`
  (`/pr-land --ignore-checks`)

Under `--dry-run`, stop here and say clearly that nothing was changed.

# 3. Apply

1. `sh ~/.claude/scripts/label-sync.sh [-R owner/repo]` — its writes prompt for
   permission on their own; that is expected. Summarize its output as `label-sync`
   would.
2. Write the planned files. Do not touch existing ones.
3. Commit the new files following the `cm` skill workflow, one commit
   (`chore(repo): add templates and CLAUDE.md skeleton for the skills`, in the
   repository's commit language). Do not push.

If the script is missing, skip the labels, say so, and continue with the files.

# Final response

Return:

- repository, visibility, default branch, CI state (`gh workflow list` empty or not; on
  GitLab, whether `.gitlab-ci.yml` exists and a pipeline has run)
- labels: created / renamed / kept counts, and unmanaged ones by name
- files created (paths) and files kept because they existed
- the commit hash, and that `/pr-ready` opens the Pull Request
- the settings list for a human, verbatim from the plan
- under `--dry-run`, that nothing was changed
