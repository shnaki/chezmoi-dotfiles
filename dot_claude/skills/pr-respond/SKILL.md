---
name: pr-respond
description: "Answer the review findings on a Pull Request after pr-fix ran in this conversation: one comment listing, per finding, the commit that fixed it or the reason it was declined. --dry-run shows the comment without posting."
argument-hint: "[pr-number] [--dry-run]"
disable-model-invocation: true
---

Tell the reviewers of the Pull Request identified by `$ARGUMENTS` what happened to
their findings. `pr-fix` fixes and pushes but posts nothing; this skill closes that
loop with a single Pull Request comment.

This skill writes exactly one comment. It does not change code, does not push, does not
merge, does not resolve review threads, and does not reply inline.

All forge operations go through the forge CLI: `gh` on GitHub, `glab` on GitLab. Before
the first such call, run `sh ~/.claude/scripts/forge-detect.sh`; it prints one line,
`<forge> <host> <path>`. On `github`, run the `gh` commands below as written. On `gitlab`,
read `~/.claude/forge/gitlab.md` once and run the `glab` equivalent it gives for each `gh`
command below, following its degrade rules where it lists none. If the script fails, stop
and report its message instead of falling back to another client.

# Core rules

- The verdicts come from a `pr-fix` result in this same conversation: which findings
  were fixed (and by which commit) and which were declined (and why). Without one,
  stop and say to run `/pr-fix` first. Do not re-decide a finding here, and do not
  answer a finding `pr-fix` did not see.
- One comment, addressed to the reviewers, in the language the repository's Pull
  Requests use. Match findings to their authors and quote enough of each finding to be
  recognizable. No tool traces.
- Never resolve a review thread or reply inline. Both need `gh api` / `glab api` writes,
  which these skills do not make; the reviewer resolves their own thread after reading
  the comment.
- Never comment on a merged or closed Pull Request.

# 0. Parse the arguments

`--dry-run` is an option, not a Pull Request number. Remove it before interpreting the
rest. With it, print the comment and stop.

Normalize what remains into a plain number: `82`, `#82`, and a full Pull Request URL
all mean Pull Request 82. Strip any leading `#` so the number is never interpolated as
`##82`. If nothing remains, resolve the Pull Request for the current branch
(`gh pr view --json number`). If that finds nothing, stop and report.

# 1. Take the verdicts from the conversation

From the most recent `pr-fix` result for this Pull Request in this conversation, list
every finding with: its source (free text, `pr-review`, `ci-review`, a GitHub review or
comment and its author), the verdict (fixed / declined), the fixing commit, or the
reason it was declined. If `pr-fix` reported findings it ignored because of
`--checks-only`, list them as "not addressed in this pass".

# 2. Read what is on GitHub

```bash
gh pr view <N> --json number,title,state,url,headRefOid,reviews,comments
```

If `state` is not `OPEN`, stop and report.

For inline review comments, read them with a GET request only:

```bash
gh api "repos/<path>/pulls/<N>/comments" --paginate
```

(`<path>` is what `forge-detect.sh` printed.) This is the one `gh api` call these
skills make (`pr-fix` uses the same one), because `gh` has no other way to list inline
review comments. It is not in the permission allow-list and prompts every time; skip it
when the user declines, and then answer only the review bodies and Pull Request
comments. On GitLab the read form is `glab api -X GET`, as `gitlab.md` gives it.

Match each GitHub finding to a `pr-fix` verdict by author, file, and wording. A GitHub
finding with no verdict is listed under "not addressed" rather than answered; a
`pr-fix` verdict with no GitHub finding (free text, `pr-review` in the conversation)
is still listed, so the comment is a complete account of the push.

Confirm the fixing commits are on the Pull Request (`gh pr view <N> --json commits`);
if `pr-fix` pushed and the commits are not there, stop and report.

# 3. Write the comment

```markdown
Addressed the review as of <headRefOid short>:

- **<author>, <file>:<line> — "<finding, shortened>"** — fixed in <sha7>: <one line
  on what changed>
- **<author> — "<finding>"** — declined: <the reason pr-fix gave>
- **<finding from ci-review>** — <fixed in <sha7> | not ours: <ci-review's evidence>>

Not addressed in this pass: <list, or omit the line>
```

One bullet per finding, fixed ones first. Keep declines factual (what the code does,
what the Issue requires); no apology, no argument. Under `--dry-run`, print the comment
and stop.

# 4. Post

Write the comment to a temporary file outside the repository (`mktemp`, or a file under
`$TMPDIR`) and post it:

```bash
gh pr comment <N> --body-file <file>
```

`gh pr comment` is a write and prompts for permission; that is expected. If it fails,
report the error verbatim and stop; do not retry.

# Final response

Return:

- Pull Request number and URL, and the comment URL
- counts: fixed / declined / not addressed
- findings that had no verdict, so the user knows a reviewer is still waiting
- under `--dry-run`, that nothing was posted
