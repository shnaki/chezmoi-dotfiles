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
- When a single file contains changes from more than one theme, stage hunk by hunk
  with `git add -p`.

## Step 4: Write the commit message

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

- `git commit --trailer "Reported-by:<name>"`
- `git commit --trailer "Github-Issue:#<number>"`

### Prohibited

- Never write `co-authored-by` or anything equivalent
- Never mention the tool used to write the commit message or the PR

## Step 5: Commit

When `$ARGUMENTS` is given, use it as input for the commit message.

```bash
git commit -m "<type>(<scope>): <subject>"
```

Use a HEREDOC when a body or footer is needed:

```bash
git commit -m "$(cat <<'EOF'
<type>(<scope>): <subject>

<body>

<footer>
EOF
)"
```

## Step 6: Verify and move to the next group

```bash
git log -1 --stat
```

- Groups remain → go back to Step 3
- All groups committed → report a summary of every commit
