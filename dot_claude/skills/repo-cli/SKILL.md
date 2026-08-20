---
name: repo-cli
description: "Translate a natural-language request into forge CLI commands (gh on GitHub, glab on GitLab) and run them. Read-only by default: write commands are refused and shown as text unless --write is given, and each write command is confirmed in the conversation before it runs."
argument-hint: "[--write] <request>"
disable-model-invocation: true
---

Turn the natural-language request in `$ARGUMENTS` into forge CLI commands, run them, and
report the results. This is the general-purpose entry point for one-off forge requests
("list the open pull requests", "show issue 82") that no specialized skill covers. When a
specialized skill does cover the whole job (reviewing, landing, triaging), still answer
the request, and name that skill in the report.

All forge operations go through the forge CLI: `gh` on GitHub, `glab` on GitLab. Before
the first such call, run `sh ~/.claude/scripts/forge-detect.sh`; it prints one line,
`<forge> <host> <path>`. On `github`, run the `gh` commands below as written. On `gitlab`,
read `~/.claude/forge/gitlab.md` once and run the `glab` equivalent it gives for each `gh`
command below, following its degrade rules where it lists none. If the script fails, stop
and report its message instead of falling back to another client. When the request needs
a command that table has no entry for, build the `glab` call from its Reading rules
(`--output json`, `--per-page`, `-R group/sub/project`); if unsure the translation is
right, show the command instead of running it.

# Core rules

- Read-only by default. A command is a write when it creates, changes, or deletes state
  on the forge or in the local repository, or starts execution on the forge (rerunning,
  cancelling, dispatching). When in doubt, treat it as a write. Writes run only under
  `--write`, and each one is confirmed first (step 3).
- Do not use `gh api`, even for reads — the regular subcommands are enough. On GitLab,
  `glab api -X GET <endpoint>` is allowed within what `gitlab.md` lists. API writes
  (POST / PUT / DELETE) stay forbidden even with `--write`; when a request needs one,
  refuse, and point at the web UI or give the command for the user to run themselves.
- The forge CLI is the only path. When a command fails, do not fall back to MCP tools,
  the web, or raw remote operations; report the failure.
- Every command that ran appears in the report, verbatim.

# 0. Parse the arguments

Options:

- `--write` — allow write commands. Remove the token; everything that remains is the
  request.

If nothing remains, report the usage in one line (`/repo-cli [--write] <request>`) and
stop. Normalize references: `82`, `#82`, and a full URL all mean number 82 — strip the
leading `#` so it is never interpolated as `##82`, and never pass a bare `#82` to a shell
command (the shell reads `#` as a comment start).

# 1. Classify the request

Decide read or write by the Core rules principle, not by a fixed list. Examples on each
side:

- Reads: `gh pr list`, `gh pr view`, `gh pr diff`, `gh pr checks`, `gh issue list`,
  `gh issue view`, `gh run list`, `gh run view`, `gh repo view`, `gh label list`,
  `gh release view`, `gh workflow list`, `gh search issues`.
- Writes: `gh pr create`, `gh pr edit`, `gh pr merge`, `gh pr comment`, `gh pr review`,
  `gh issue create`, `gh issue edit`, `gh issue close`, `gh issue comment`,
  `gh release create`, `gh run rerun`, `gh run cancel`, `gh workflow run`, and
  `gh pr checkout` — it changes the local repository.

When the request mixes both ("look at the failing checks and rerun them"), the read part
runs normally and the write part follows the write path.

When one interpretation is clearly the best, take it and name it in the report. When
interpretations genuinely diverge — which repository, issues or pull requests, open or
everything — do not guess and run; present two or three candidate commands with what
each would return, and ask.

# 2. Build the commands

- Prefer structured output: `--json` with exactly the fields the answer needs, plus
  `--jq` when it shortens the result.
- List commands default to `--limit 30` unless the request names an amount.
- An `owner/repo` mentioned in the request becomes `-R owner/repo` on every call;
  otherwise the current repository is the target.
- Read chains within one request are fine: list then view the interesting item, follow
  pagination when the request asks for everything.

# 3. Execute

Reads run immediately, without asking. The permission system is the gate for anything
outside the allow-list; this skill adds no confirmation of its own for reads.

A write without `--write` does not run. Show the exact command in a code block and offer
the two ways forward — the user runs it themselves, or reruns this skill as
`/repo-cli --write <same request>` — then stop.

A write with `--write`: show the full command and what it will change, wait for the
user's agreement in the conversation, then run it. One command per agreement — never
bundle several writes into one yes. On GitLab, follow the non-interactive rules of
`gitlab.md` (`--yes`, never open an editor).

# 4. Report

- The commands that ran, and the results summarized — quote the lines that answer the
  request, do not paste whole outputs.
- The interpretation taken, when the request left room for more than one.
- On a command failure: the command, its exit code, the relevant stderr lines, the
  likely cause (not authenticated, wrong number, missing permission), and the next step.
- When the skill refused a write or only read, say explicitly that nothing on the forge
  was changed.
