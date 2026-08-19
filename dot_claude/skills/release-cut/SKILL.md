---
name: release-cut
description: "Cut a GitHub release from what merged since the last tag: propose the next version from Conventional Commits, draft categorized release notes, and create the release and tag with gh; --dry-run only proposes."
argument-hint: "[--dry-run] [--tag <version>] [--draft] [-R owner/repo]"
disable-model-invocation: true
---

Cut a release for the repository: collect what landed on the base branch since the last
release, propose the next version, write the release notes, and create the release.

Invoking this skill without `--dry-run` is the authorization to create the release and
its tag. Do not ask for confirmation again before creating, unless step 4 says so.

This skill does not change the code. It does not commit, does not edit `CHANGELOG.md`
or version files, and does not push. The tag is created by `gh release create` on
GitHub, never with `git tag` / `git push --tags` here.

All forge operations go through the forge CLI: `gh` on GitHub, `glab` on GitLab. Before
the first such call, run `sh ~/.claude/scripts/forge-detect.sh`; it prints one line,
`<forge> <host> <path>`. On `github`, run the `gh` commands below as written. On `gitlab`,
read `~/.claude/forge/gitlab.md` once and run the `glab` equivalent it gives for each `gh`
command below, following its degrade rules where it lists none. If the script fails, stop
and report its message instead of falling back to another client.

# 0. Parse the arguments

Options:

- `--dry-run` — do everything up to the plan (step 4), print the proposed tag and the
  full release notes, create nothing.
- `--tag <version>` — use this tag instead of the proposed one. Accept `1.4.0` and
  `v1.4.0`; keep the repository's own prefix convention (step 1).
- `--draft` — create the release as a draft, so it can be edited on GitHub before it is
  published. GitLab has no draft releases: on `gitlab`, stop and report that instead of
  creating a published release.
- `-R owner/repo` — target another repository. Pass it to every `gh` call; local `git`
  commands then need a checkout of that repository and are skipped when there is none
  (say so, and rely on `gh` alone).

Anything else is an error: stop and report.

# 1. Find the previous release and the conventions

```bash
gh release list --limit 20 --json tagName,isDraft,isPrerelease,isLatest,publishedAt
git fetch --tags origin
git tag --sort=-creatordate | head -20
gh repo view --json defaultBranchRef --jq .defaultBranchRef.name
```

Determine:

- the base branch (the default branch unless the repository releases from another
  branch — CLAUDE.md, CONTRIBUTING.md, or the tags' history says so)
- the previous release: the newest entry with `isDraft` and `isPrerelease` both false
  (`isLatest` when GitHub marks one); if there is none, the newest tag; if there is
  neither, this is the first release and the range starts at the root commit
- when `--tag` was given: that the tag does not exist yet (`git tag -l <tag>` empty and
  `gh release view <tag>` failing). If it exists, stop and report now, before doing any
  of the work below; do not move or delete a tag
- the tag convention: `v1.2.3` or `1.2.3`, and any prefix or suffix the existing tags use
- whether `CHANGELOG.md` (or `CHANGES.md`, `HISTORY.md`) exists and its format
- how existing release notes are written (`gh release view <tag>`): language, headings,
  whether Pull Request numbers or commit hashes are cited

Match those conventions. When there is no previous release, use `v` + semver unless a
version file in the repository (`package.json`, `pyproject.toml`, `Cargo.toml`, …) says
otherwise.

# 2. Collect what landed

```bash
gh pr list --state merged --base <base> --limit 400 \
  --json number,title,mergedAt,mergeCommit,labels,body,url
git log <previous-tag>..origin/<base> --format='%H%x09%P%x09%s%x09%b'
```

The merged Pull Requests are the primary list. Keep those whose `mergedAt` is after the
previous release (compare with `gh release view <previous-tag> --json publishedAt`, or
the tag's commit date). If `gh pr list` returned as many entries as `--limit`, the list
may be truncated (it is sorted by creation, not by merge date): stop and report rather
than release from an incomplete list.

Then walk the `git log` range — merge commits included, since a repository that merges
with merge commits has the `(#N)` on the merge commit itself — and match each commit to
a Pull Request by `mergeCommit.oid`, by `(#N)` in the subject, or by being reachable
only through a matched merge commit (a second parent's history). Only a commit that
matches no Pull Request at all is listed on its own; the individual commits inside a
merged Pull Request are not separate entries.

For each entry, determine the type from, in order:

1. the Conventional Commits prefix of the Pull Request title, or of the squash / merge
   commit subject
2. the type label on the Pull Request (`type/bug` → fix, `type/feature` → feat, …)
3. the prefixes of the commits inside the Pull Request

Note `!` after the type and `BREAKING CHANGE:` footers.

Skip nothing silently: entries whose type cannot be determined go under Other.

# 3. Propose the version and write the notes

Version bump, from the collected entries:

- any breaking change → major (or minor while the major is `0`, if the repository has
  been doing that)
- otherwise any `feat` → minor
- otherwise → patch

`--tag` overrides the proposal. Say what the proposal would have been.

Notes, in the language and shape of the repository's existing releases (step 1). When
there is no precedent:

```markdown
## Breaking changes
- <what changed and what to do about it> (#N)

## Features
- <subject> (#N)

## Fixes
- <subject> (#N)

## Other
- <subject> (#N)          docs / refactor / perf / test / chore / build / ci / style, and unclassified

**Full changelog**: <compare URL: https://<host>/<path>/compare/<previous-tag>...<new-tag> on GitHub, https://<host>/<path>/-/compare/<previous-tag>...<new-tag> on GitLab>
```

Rules for the notes:

- One line per Pull Request (or per commit without a Pull Request), citing `(#N)`.
  Reword subjects only to strip the type prefix and to read as one list; do not merge
  or drop entries.
- Omit empty sections. Omit the compare line for a first release.
- Write for the user of the software, not for the author of the commits: state the
  visible effect, not the file that changed.
- Do not name the tools used to do the work anywhere in the notes.

If a changelog file exists in a recognizable format (Keep a Changelog, or the
repository's own), also prepare the entry that would go under a new heading for this
version. Print it in the report as a suggestion. Do not edit the file: a changelog
change belongs in a Pull Request, not in this skill.

# 4. Print the plan

Before creating anything, print:

- previous release / tag, and the range used
- proposed tag (and what `--tag` overrode, if anything)
- the counts per section
- the full release notes
- the changelog entry suggestion, if any
- whether the release will be a draft

Under `--dry-run`, stop here and say clearly that nothing was created.

Ask once before continuing when the range holds more than 200 entries or spans more
than one previously released tag (that usually means the previous release was misread).
Otherwise do not ask.

# 5. Create the release

Write the notes to a temporary file outside the repository (never inside the working
tree) and create the release, which also creates the tag on the base branch:

```bash
gh release create <tag> --target <base> --title "<tag>" --notes-file <file>
```

Add `--draft` when requested. Use `--title` in the repository's convention when
existing releases title differently from the tag. Do not pass `--generate-notes`; the
notes are the ones written in step 3.

Check once more that the tag does not exist (`git tag -l <tag>` empty, `gh release view
<tag>` failing) — the proposed tag was not known in step 1 — and stop and report if it
does; do not move or delete a tag.

If `gh release create` fails, report the error verbatim and stop. Do not retry with a
different tag to get past it.

# Report

Return:

- the release URL, tag, target branch, and whether it is a draft
- previous release and the range
- counts per section, and entries whose type had to be guessed
- the changelog entry suggestion, if any, and that the file was not edited
- under `--dry-run`, that nothing was created
