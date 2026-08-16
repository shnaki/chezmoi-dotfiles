---
name: ship-notes
description: "Turn notes into GitHub Issues and then orchestrate implementation of the created Issues as isolated Pull Requests."
argument-hint: "[--merge] [notes-file-or-text]"
disable-model-invocation: true
---

Process the notes in `$ARGUMENTS` from triage through Pull Request creation.

If `$ARGUMENTS` begins with `--merge`, remove that token and treat the rest as the
notes. The option is passed on to the `ship-issues` phase, which then lands each wave's
Pull Requests instead of stopping at Pull Request creation.

# Workflow

1. Triage the notes using the same workflow defined by `triage-notes`.
2. Create the resulting GitHub Issues.
3. Collect only the newly created actionable Issue numbers.
4. Process those Issues using the same workflow defined by `ship-issues`, passing
   `--merge` through when it was given.
5. Return the combined result.

# Boundaries

- Do not implement anything during the triage phase.
- Do not alter Issue boundaries after implementation begins merely to make the work easier.
- Do not include duplicate, obsolete, or non-actionable notes in the implementation phase.
- One Issue must result in at most one Pull Request.
- Do not merge Pull Requests unless `--merge` was given, and then only through the
  `ship-issues` phase.

# Final response

Return:

- created Issues
- notes that did not create Issues and why
- Pull Requests created for actionable Issues
- blocked or deferred Issues
- merge state of each Pull Request, when `--merge` was given
- execution waves and important dependencies
