# Labeling rules

Shared rules for choosing GitHub labels for one Issue or Pull Request. Used by
`label-apply` (bulk re-labeling), by the skills that create or edit Issues and Pull
Requests (`triage-notes`, `issue-refine`, `issue-pr`, `pr-ready`, `pr-describe`,
`backlog-apply`, `repo-bootstrap`), and by `backlog-review` (which only reads them).
Read this file by path. Another skill may summarize what it needs from these rules in
one line ("one type label from the repository's vocabulary; a status label only on the
rules' evidence"), but must not restate the rules themselves: when the summary and this
file disagree, this file wins.

The rules work with **whatever labels the repository already has**. They do not
require the default set that `label-sync` installs. If nothing in the repository fits,
add nothing.

# 1. Discover the vocabulary

```bash
gh label list --limit 500 --json name,description,color
```

Do this once per run. Never create, rename, or delete a label here. Only labels
returned by that command may be applied.

Resolve four categories from the names and descriptions:

| Category | Default set | Common equivalents when the default set is absent |
| --- | --- | --- |
| type | `type/bug`, `type/feature`, `type/refactor`, `type/perf`, `type/docs`, `type/test`, `type/chore` | `bug`, `enhancement` / `feature`, `documentation` / `docs`, `refactor`, `test`, `chore`; also `kind/*`, `type:*`, `type: *` prefixes with the same meanings |
| priority | `priority/high`, `priority/medium`, `priority/low` | `P0`–`P3`, `priority:*`, `urgent`, `high priority`, … |
| status | `status/blocked`, `status/needs-info`, `status/duplicate`, `status/wontfix` | `blocked`, `question` (= needs-info), `duplicate`, `wontfix`, `invalid` (do not apply), `stale` (do not apply) |
| flags | `dependencies`, `security`, `breaking-change`, `good first issue`, `help wanted` | `deps`, `breaking`, `security` |

A label belongs to a category only when its name or description makes the meaning
clear. When it is ambiguous, treat it as outside every category: never add it, never
remove it.

Managed labels are the ones resolved into `type`, `priority`, and `status`. Everything
else — flags included — is touched only when explicitly listed in these rules; labels
outside every category are never touched.

# 2. Choose the type (exactly one, when a type vocabulary exists)

Evidence, in order of strength:

1. A Conventional Commits prefix on the Pull Request title, or on every commit in the
   Pull Request when the title has none:

   | prefix | type |
   | --- | --- |
   | `fix` | bug |
   | `feat` | feature |
   | `refactor` | refactor |
   | `perf` | perf |
   | `docs` | docs |
   | `test` | test |
   | `chore`, `build`, `ci`, `style` | chore |
   | `revert` | the type of the reverted change if it is stated; otherwise chore |

   With `!` after the type or a `BREAKING CHANGE:` footer, also apply the
   breaking-change flag if the repository has one.

2. For a Pull Request, the type label already on the Issue it closes
   (`closingIssuesReferences`, or `Closes #N` in the body).

3. The content: a defect with actual/expected behavior is bug; a new capability or a
   change to existing behavior is feature; documentation-only, tests-only,
   restructuring without behavior change, and maintenance map to docs / test /
   refactor / chore. Mixed content takes the label of its primary purpose.

When the type vocabulary is flat (`bug` / `enhancement` only), map bug → `bug` and
everything else → `enhancement`, except documentation → `documentation` when that
label exists. Do not stretch: a refactor with only `bug` and `enhancement` available
gets `enhancement` only if the repository already uses it that way (check a few
recently closed Issues); otherwise leave the type empty and say so.

An item ends up with **at most one** type label. If it already has exactly one and
the evidence above does not contradict it, keep it. If it has two or more, keep the
one the evidence supports and remove the rest. Replace an existing one only when the
evidence is stronger than "the body reads more like X" — a Conventional Commits
prefix or the linked Issue's label counts; a hunch does not.

# 3. Priority (at most one, only with explicit evidence)

Apply a priority only when the title, body, or a maintainer comment states it in
words (`urgent`, `P0`, `blocker`, `high priority`, `low priority`, `nice to have`,
「至急」「優先度低」…). Do not infer priority from severity, age, or reactions.
Never remove a priority label a human set.

# 4. Status (at most one, only with explicit evidence)

- blocked — the body or a comment says it depends on / is blocked by another Issue,
  Pull Request, or external change, and that dependency is still open. Remove
  `blocked` when the named dependency is closed or merged.
- needs-info — the last maintainer comment asks the reporter for information and no
  reply followed, or the item is a question with no actionable request.
- duplicate — closed, and a comment or `stateReason` explains it duplicates another
  item (name the target).
- wontfix — closed as `NOT_PLANNED` with an explicit statement that it will not be
  addressed. `NOT_PLANNED` alone is not enough.

Never remove a status label without evidence that the condition no longer holds.

# 5. Flags

- dependencies — the author is Dependabot or Renovate, or the diff touches only
  dependency manifests and lockfiles.
- security — the text names a vulnerability, CVE, advisory, or security hardening.
- breaking-change — see step 2.
- `good first issue`, `help wanted` — never added or removed automatically.

# 6. What not to do

- Do not create labels. If a category has no label in the repository, skip it.
- Do not touch labels outside the resolved categories (`area/*`, `component/*`,
  release labels, bot labels, …).
- Do not remove a managed label without evidence, and never remove more than the
  rules above name.
- Do not edit titles, bodies, comments, assignees, milestones, or state.
- When the evidence is thin, add nothing and report the item as undecided with the
  reason. Fewer confident labels beat many guesses.
