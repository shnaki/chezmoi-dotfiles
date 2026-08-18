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

All GitHub operations go through the GitHub CLI (`gh`). Do not use another GitHub
client. If `gh` is unavailable or not authenticated, stop and report instead of falling
back.

# 0. Parse the arguments

Options:

- `--dry-run` — do everything up to the plan (step 4), print the proposed tag and the
  full release notes, create nothing.
- `--tag <version>` — use this tag instead of the proposed one. Accept `1.4.0` and
  `v1.4.0`; keep the repository's own prefix convention (step 1).
- `--draft` — create the release as a draft, so it can be edited on GitHub before it is
  published.
- `-R owner/repo` — target another repository. Pass it to every `gh` call; local `git`
  commands then need a checkout of that repository and are skipped when there is none
  (say so, and rely on `gh` alone).

Anything else is an error: stop and report.

# 1. Find the previous release and the conventions

```bash
gh release list --limit 20
git fetch --tags origin
git tag --sort=-creatordate | head -20
gh repo view --json defaultBranchRef --jq .defaultBranchRef.name
```

Determine:

- the base branch (the default branch unless the repository releases from another
  branch — CLAUDE.md, CONTRIBUTING.md, or the tags' history says so)
- the previous release: the newest non-draft, non-prerelease release; if there is none,
  the newest tag; if there is neither, this is the first release and the range starts at
  the root commit
- the tag convention: `v1.2.3` or `1.2.3`, and any prefix or suffix the existing tags use
- whether `CHANGELOG.md` (or `CHANGES.md`, `HISTORY.md`) exists and its format
- how existing release notes are written (`gh release view <tag>`): language, headings,
  whether Pull Request numbers or commit hashes are cited

Match those conventions. When there is no previous release, use `v` + semver unless a
version file in the repository (`package.json`, `pyproject.toml`, `Cargo.toml`, …) says
otherwise.

# 2. Collect what landed

```bash
git log <previous-tag>..origin/<base> --no-merges --format='%H%x09%s%x09%b'
gh pr list --state merged --base <base> --limit 200 \
  --json number,title,mergedAt,mergeCommit,labels,body,url
```

Keep the Pull Requests whose `mergedAt` is after the previous release (compare with
`gh release view <previous-tag> --json publishedAt`, or the tag's commit date). Match
commits to Pull Requests by `mergeCommit` and by `(#N)` in the subject; a commit with
no Pull Request is listed on its own.

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

**Full changelog**: <compare URL: https://github.com/<owner>/<repo>/compare/<previous-tag>...<new-tag>>
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

If the tag already exists (`git tag -l <tag>` or `gh release view <tag>` succeeds), stop
and report before creating anything; do not move or delete a tag.

If `gh release create` fails, report the error verbatim and stop. Do not retry with a
different tag to get past it.

# Report

Return:

- the release URL, tag, target branch, and whether it is a draft
- previous release and the range
- counts per section, and entries whose type had to be guessed
- the changelog entry suggestion, if any, and that the file was not edited
- under `--dry-run`, that nothing was created
