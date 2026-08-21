---
name: repo-init
description: "Initialize a local git repository with an empty initial commit so the first real commit stays rebasable."
argument-hint: "[path]"
disable-model-invocation: true
---

Initialize a local git repository and create an empty initial commit.

The empty root commit exists so that every later commit — including the first
real one — can be rebased, squashed, or reworded without special-casing the
root. Local only: never create a forge repository, never add a remote, never
push, and never run `gh` / `glab`. Creating the forge repository and the rest
of the setup is `/repo-bootstrap`'s job.

# 1. Resolve the target directory

- If `$ARGUMENTS` contains a path, that directory is the target. Create it
  (including parents) when it does not exist yet.
- With no arguments, the target is the current working directory.

# 2. Stop if it is already a repository

Run inside the target directory:

```
git rev-parse --is-inside-work-tree
```

If this succeeds, the target already is (or is contained in) a git repository.
**Stop and report** the repository root (`git rev-parse --show-toplevel`);
do not run `git init` again and do not add another initial commit.

# 3. Initialize

```
git init
```

Do not pass `-b` / `--initial-branch`: the branch name follows the user's
`init.defaultBranch` configuration.

# 4. Create the empty initial commit

```
git commit --allow-empty -m "Initial commit"
```

The message is fixed to `Initial commit`; the Conventional Commits format does
not apply to this root commit. Do not stage anything: files already present in
the directory stay uncommitted, and committing them is `/cm`'s job.

# Final response

Report:

- the repository path and the branch name
- the initial commit hash (`git log --oneline`)
- the number of uncommitted files, if any (`git status --short`)
- next steps, without running them: `/cm` to commit existing files, and
  `/repo-bootstrap` once a forge repository exists and `origin` is set
