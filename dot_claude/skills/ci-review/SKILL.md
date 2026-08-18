---
name: ci-review
description: "Investigate failing GitHub Actions checks on a Pull Request, a run, or a branch and classify each failure as pr-caused / pre-existing / flaky / infrastructure (including billing) / ci-definition / needs investigation. Read-only: reports and suggests next commands, changes nothing on GitHub."
argument-hint: "[pr-number | --run <run-id> | --branch <name>] [--workflow <name>] [-R owner/repo]"
disable-model-invocation: true
---

Investigate the failing checks selected by `$ARGUMENTS` and sort each one into exactly
one class, so the user knows which failures the Pull Request has to fix, which were
already broken, which can just be re-run, and which need a human.

This skill only reads. It is the step before `/pr-fix` (which fixes what the Pull Request
caused) and `/triage-notes` (which files an Issue for what it did not). It hands the
classification to those; it does not do their work.

All GitHub operations go through the GitHub CLI (`gh`). Do not use another GitHub
client. Before the first `gh` call, run `gh auth status`; if `gh` is unavailable or not
authenticated, stop and report instead of falling back.

# Core rules

- Read-only. Never run `gh run rerun`, `gh run cancel`, `gh workflow run`,
  `gh pr comment`, or any other write. Do not create branches, worktrees, or commits,
  and do not fix anything. Fixing is `pr-fix`.
- Do not use `gh api`, even for reads. `gh pr view`, `gh pr checks`, `gh run list`,
  `gh run view`, and `gh workflow list` are enough.
- Every failing check gets exactly one class. When the evidence does not decide, use
  `needs investigation` and say what would decide it. Never call a failure `pr-caused`
  or `flaky` by guessing.
- Read the repository's code only as far as a class needs it: to see whether the
  failing step touches files the Pull Request changed. Do not start fixing.
- Do not paste whole logs. Quote the lines that show the failure.

# 0. Parse the arguments

Options:

- `--run <run-id>` — investigate this one workflow run.
- `--branch <name>` — investigate the latest failing runs on this branch (default
  branch failures, scheduled workflows).
- `--workflow <name>` — only checks or runs of this workflow. Pass it to `gh run list`;
  for a Pull Request, filter the `gh pr checks` output on its `workflow` field (that
  command has no `--workflow` flag).
- `-R owner/repo` — target another repository. Pass it to every `gh` call. The command
  examples below show it once and then leave it out.

Everything else is a Pull Request selector: `82`, `#82`, or a full Pull Request URL all
mean Pull Request 82. Strip the leading `#` so the number is never interpolated as
`##82`, and never pass a bare `#82` to a shell command.

With neither a selector nor `--run` / `--branch`, resolve the Pull Request for the
current branch (`gh pr view --json number`). If there is none, treat the current branch
as `--branch <current>`.

# 1. List the failing checks

For a Pull Request:

```bash
gh pr view <N> [-R owner/repo] --json number,title,url,headRefName,headRefOid,baseRefName,files
gh pr checks <N> [-R owner/repo] --json name,state,bucket,workflow,link,startedAt,completedAt
```

Read the output of `gh pr checks`, not its exit code: it exits 1 when a check failed,
8 while checks are pending, and 1 with `No checks reported on the '<branch>' branch`
when there are none. When it reports no checks, GitHub Actions is disabled for the
repository or no workflow runs for this event; confirm with `gh workflow list` (empty,
or every workflow inactive), report `no checks: Actions disabled or no workflows`, and
stop — there is nothing to classify.

Keep the checks whose `bucket` is `fail` (or `state` is `FAILURE` / `ERROR` /
`TIMED_OUT` / `CANCELLED` / `ACTION_REQUIRED` / `STARTUP_FAILURE` / `STALE`). If none,
report that all checks passed (or are still running: name the pending ones) and stop.
The run id is the number after `/runs/` in `link`; checks that are not GitHub Actions
runs (external status checks) have no run to read: classify them from their `link` and
name only, and say so.

`files` is capped at 100 entries. When the Pull Request changes more, use
`gh pr diff <N> --name-only` for the file list instead.

For `--run <id>`: that run alone. For `--branch <name>`:

```bash
gh run list --branch <name> [--workflow <w>] --status failure --limit 5 \
  --json databaseId,name,workflowName,headSha,event,conclusion,createdAt,url
```

For every run to investigate:

```bash
gh run view <id> --json name,workflowName,headSha,event,attempt,conclusion,jobs,url
```

`jobs[].steps[]` gives the failing job and step names.

# 2. Read the failure

```bash
gh run view <id> --log-failed
```

The output can be very large. Do not read or quote it whole. Find the failing step from
step 1, then look at the last part of that step's log and at lines matching
`error`, `Error:`, `FAIL`, `failed`, `exit code`, `Process completed with exit code`,
`##[error]`. Identify:

- the failing step and the command it ran
- the first real error (not the cascade after it)
- the file or test the error names, if any

When `--log-failed` answers `log not found: <job-id>`, the job never ran. Read the run
without its log:

```bash
gh run view <id>
```

Its ANNOTATIONS section carries the reason. `The job was not started because recent
account payments have failed or your spending limit needs to be increased` means the
account is out of GitHub Actions minutes (a billing failure, classified under
`infrastructure` below); a runner-label or permission message means another kind of
`infrastructure`. In `--json jobs` such a job has `conclusion: failure` and an empty
`steps` array.

If the log is gone (expired) or the run was cancelled before it produced one, note that;
it usually pushes the class toward `needs investigation` or `infrastructure`.

# 3. Compare with the base

Take the base branch (`baseRefName` for a Pull Request; the default branch for
`--run` / `--branch`) and fetch the recent runs of the same workflow there:

```bash
gh run list --branch <base> --workflow "<workflowName>" --limit 5 \
  --json databaseId,headSha,conclusion,createdAt,url
```

When the target *is* the default branch (`--branch main`, or `--run` on a run from it),
there is no separate base to compare with. Instead, list more runs of the workflow on
that branch (`--limit 20`), find the latest green one, and treat the commits between its
`headSha` and the failing run's `headSha` as the candidates that introduced the failure
(`git log <green-sha>..<failing-sha> --oneline` when a local checkout exists).

Also fetch the runs of the same workflow on the head branch itself:

```bash
gh run list --branch <headRefName> --workflow "<workflowName>" --limit 10 \
  --json databaseId,headSha,conclusion,attempt,url
```

A run with the same `headSha` as the failing one that concluded `success` is the
evidence for `flaky` in step 4. (`attempt` only reports the current attempt number; the
result of an earlier attempt is not available without `gh api`, so do not cite it.)

When the latest base run of that workflow also failed, read its `--log-failed` the same
way as step 2, only far enough to see whether it is the same step and the same error.

For a Pull Request, compare the failing step's subject (the file, test, package, or
lint rule it names) with `files` from step 1: does the Pull Request touch it, or a
dependency of it that is obvious from the diff?

# 4. Classify

Apply the classes in this order; the first one whose evidence holds wins.

1. `infrastructure` — the failure happens before or outside the repository's own
   commands: runner could not start or was lost (`The hosted runner encountered an
   error`, `The operation was canceled` with no preceding error), missing or empty
   secret, permission denied against GitHub itself, rate limit, artifact or cache
   service unavailable, network failure while installing tools. Evidence names the
   message.

   **Billing** is the most common form on private repositories: the annotation `The job
   was not started because recent account payments have failed or your spending limit
   needs to be increased`, `log not found` from `--log-failed`, and an empty `steps`
   array together mean the account is out of Actions minutes. Use the evidence form
   `billing: job not started (spending limit)` so `pr-fix` and `pr-land` can tell it
   apart from other infrastructure failures. It says nothing about the code.
2. `ci-definition` — the workflow definition itself is wrong: `Invalid workflow file`,
   an unresolvable action or version, a bad expression, a job that references a missing
   input. When the Pull Request changed that workflow file, classify as `pr-caused`
   instead and say which file.
3. `flaky` — another run of the same workflow on the same `headSha` concluded
   `success` (step 3), or the latest base run of the workflow is green and the error is
   a timeout, an external service, a port or file already in use, or a test the
   repository marks as flaky. Never `flaky` on the strength of "it looks unrelated"
   alone; name the green run of the same commit or the green base run.
4. `pre-existing` — the latest base run of the same workflow fails at the same step
   with the same error. Evidence names the base run.
5. `pr-caused` — the base run is green (or the failing step's subject is in the Pull
   Request's diff) and the error names something the Pull Request changed. For
   `--run` / `--branch` on the default branch, use `pr-caused` when the failure started
   with an identifiable commit and name that commit.
6. `needs investigation` — none of the above can be decided from the evidence at hand.
   The note names what would decide it (`base has no run of this workflow`, `log
   expired`, `error names a file the PR does not touch, but base is green`, …).

# 5. Report

Report in the conversation only. Do not write a file.

Open with what was investigated (Pull Request number and URL, or run id, or branch;
workflow filter; repository when `-R` was given) and the counts: failing checks, then
one count per class.

Then one table, one row per failing check or run:

```
| check | run | class | evidence | note |
```

`run` is the run id (so the suggested `gh run rerun <run-id>` lines below can be matched
to a row), or `-` for an external status check. `evidence` names the fact that decided
the class, in a short fixed form: `base run <url> green`, `same error on base <sha-7>`,
`same sha passed in run <id>`, `runner error before checkout`, `billing: job not
started (spending limit)`, `changes <path> in this PR`, `Invalid workflow file`,
`log expired`. `note` carries the extras: the failing step, the first error line
(quoted, one line), the commit that introduced it, or what is missing.

Under the table, for each row, quote the few log lines that show the failure (the
command, the first error, the file or test named). Not more than about ten lines per
row.

Then **Suggested next commands**, as text the user can run, never executed by this
skill:

- `/pr-fix <N> --checks-only` when any check is `pr-caused` and the target is a Pull
  Request. For `--run` / `--branch`, `/triage-notes "<one-line summary>"` and then
  `/issue-pr` on the Issue; never fix the default branch directly
- `/triage-notes "<one-line summary naming the workflow, step, and error>"` for each
  `pre-existing` and `ci-definition` failure, so it becomes an Issue instead of being
  re-discovered on the next Pull Request
- `gh run rerun <run-id> --failed` for each `flaky` run, one line per run, ready to
  paste
- for `infrastructure`: what a human has to check (the secret name, the runner label,
  the service), in one line. For a billing failure: `Settings → Billing & plans` on the
  account, and — when the Pull Request itself is fine and only has to land —
  `/pr-land <N> --ignore-checks`, which merges without waiting for checks that cannot
  run. Not for other classes.
- for `needs investigation`: the one thing to look at next

End with the sentence: `Nothing was changed on GitHub.`
