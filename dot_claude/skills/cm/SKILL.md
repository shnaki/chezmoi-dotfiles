---
name: cm
description: "Commit changes using the Conventional Commits format. Use when committing code changes."
user-invocable: true
argument-hint: "[commit message or description of the change]"
---

# Conventional Commit

# Instructions

Commit the current changes using the Conventional Commits format. When the repository
already follows a different commit convention (its `git log`, CLAUDE.md, or
CONTRIBUTING.md say so), follow the repository instead of the format below.

## Step 1: Review the changes

```bash
git status
git diff --staged
git diff
git log --oneline -20
```

Understand every change before proceeding. The recent log also shows the language and
style the repository's commit messages use; step 4 follows it.

Stop and report instead of committing when:

- there is nothing to commit (no staged or unstaged change)
- HEAD is detached (`git symbolic-ref --quiet HEAD` fails): say so and let the user pick
  a branch; do not commit onto a detached HEAD
- something is already staged that does not belong to the group being committed:
  unstage it (`git restore --staged <file>`) rather than sweeping it into the commit,
  and mention it

## Step 2: Classify and group the changes

Group the changes by logical theme.

### Grouping criteria

- **By feature**: changes belonging to the same feature form one group
- **By kind**: documentation, tests, and refactoring belong in separate groups
- **By dependency**: when one change depends on another, commit the dependency first

### Decision

- All changes fit a single theme → go straight to Step 3 as one commit. Do not ask
  for confirmation; the grouping is obvious, and stopping here is just noise.
- The changes must be split into multiple groups → present the proposed split and
  get confirmation before proceeding. Then repeat Steps 3-5 for each group.
- The split is unclear, or the working tree contains changes whose intent cannot be
  determined → get confirmation before proceeding.

## Step 3: Stage

Stage only the files belonging to the current group:

```bash
git add <file1> <file2> ...
```

- Never use `git add -A` or `git add .`. Name the target files explicitly.
- When a single file contains changes from more than one theme, stage only the hunks
  of the current theme. `git add -p` is interactive and cannot run from a tool shell,
  so build the partial patch instead: `git diff <file> > <tmp>.patch`, delete the
  hunks that belong to other themes from the file (keep the `diff --git` / `---` /
  `+++` header), then `git apply --cached <tmp>.patch`. Check the result with
  `git diff --staged <file>` before committing.

## Step 4: Write the commit message

When `$ARGUMENTS` is given, use it as the input for the message: a ready-made message
is used as written (after checking it against the format below), a description of the
change is turned into one.

### Format

```
<type>(<scope>)?: <subject>

<body>

<footer>
```

### type (required)

- `feat`: new feature
- `fix`: bug fix
- `docs`: documentation change
- `refactor`: internal improvement with no behavior change
- `test`: adding or fixing tests
- `chore`: chores and maintenance
- `ci`: CI configuration change
- `build`: build or dependency change
- `perf`: performance improvement
- `style`: formatting only, no code change
- `revert`: reverting a change

### scope (optional)

The area affected by the change. Omit it when it adds nothing.

### language

Write the subject and body in the language the repository's existing commits use
(`git log` from step 1). When the repository has no established convention, write them
in Japanese.

### subject (required)

- Concise
- No trailing punctuation

### body (optional)

- Explain the reason and background of the change
- Describe why the change was made, not what was changed
- Full sentences with trailing punctuation

### footer (only when applicable)

- Breaking changes: use the `type(scope)!: ...` form, or put `BREAKING CHANGE:` in the body
- Trailers such as `Reported-by: <name>` or `Github-Issue: #<number>` go last, one per
  line (step 5 shows how to pass them)

### Prohibited

- Never write `co-authored-by` or anything equivalent
- Never mention the tool used to write the commit message or the PR

## Step 5: Commit

Subject only:

```bash
git commit -m "<type>(<scope>): <subject>"
```

When a body or footer is needed, write the whole message to a temporary file outside
the repository (`mktemp`, or a file under `$TMPDIR`) and commit from it. This works from
any tool shell; a shell HEREDOC does not (the PowerShell tool has a different here-string
syntax):

```bash
git commit -F <tmp>/commit-msg.txt
```

Trailers can also be added on the command line instead of in the file:

```bash
git commit -F <tmp>/commit-msg.txt --trailer "Github-Issue:#<number>"
```

Delete the temporary file afterwards.

## Step 6: Verify and move to the next group

```bash
git log -1 --stat
```

If a commit hook rejects the commit, report the hook's output and stop; do not bypass it
with `--no-verify`.

- Groups remain → go back to Step 3
- All groups committed → report a summary of every commit
