---
name: pr-review
description: "Independently review a Pull Request for correctness, regressions, scope violations, and missing verification without modifying the implementation."
argument-hint: "[pr-number]"
disable-model-invocation: true
---

Independently review Pull Request #$ARGUMENTS.

Act as a reviewer, not as the implementation author.

Do not modify files.
Do not push commits.
Do not merge the Pull Request.

# 1. Read the Pull Request

Read:

- title
- description
- linked Issue
- relevant discussion
- commit list when useful

Understand the intended behavior before reviewing the implementation.

# 2. Read the linked Issue

Determine:

- problem being solved
- expected behavior
- acceptance criteria
- explicit scope
- explicit out-of-scope work

The Issue is the primary scope boundary.

# 3. Inspect the complete diff

Review the full Pull Request diff against its base branch.

Do not review only individual changed snippets in isolation.

Inspect surrounding code when necessary to understand behavior.

# 4. Review correctness

Look for concrete problems such as:

- incorrect behavior
- incomplete acceptance criteria
- edge cases
- incorrect error handling
- invalid assumptions
- state-management bugs
- race conditions
- resource leaks
- data-loss risks
- security regressions
- compatibility regressions

Prioritize observable and actionable problems.

# 5. Review scope

Check for changes unrelated to the linked Issue.

Flag:

- unrelated refactoring
- unnecessary cleanup
- unrelated formatting
- unrelated dependency changes
- unrelated behavior changes
- speculative architecture changes

Do not flag necessary supporting changes merely because they touch additional files or layers.

# 6. Review repository conventions

Check applicable:

- CLAUDE.md
- `.claude/rules/`
- repository conventions
- architecture patterns
- generated-code rules
- testing conventions

Flag meaningful violations.

# 7. Review tests and verification

Determine whether the Pull Request has sufficient regression protection.

Look for:

- missing tests for changed behavior
- tests that do not exercise the actual failure mode
- weakened assertions
- disabled tests
- skipped tests
- excessive mocking that bypasses the behavior under test
- missing relevant integration coverage

Do not demand tests mechanically when the repository or type of change does not warrant them.

# 8. Look for accidental artifacts

Check for:

- debug logging
- temporary files
- commented-out code
- accidental generated-file changes
- accidental lock-file changes
- secrets
- local environment paths
- machine-specific configuration

# 9. Verify findings

Before reporting an issue:

- inspect enough surrounding code to confirm it
- distinguish facts from speculation
- avoid reporting stylistic preferences as defects
- avoid duplicate findings
- avoid hypothetical concerns with no plausible failure path

Prefer a small number of high-confidence findings over a large number of weak observations.

# Severity

Classify findings as:

## Critical

Likely to cause severe security, data-loss, or system-wide failure.

## High

Likely to cause incorrect behavior, significant regression, or failure of a core acceptance criterion.

## Medium

A real defect or meaningful maintainability problem that should normally be fixed before merge.

## Low

A valid but limited problem that may reasonably be fixed later.

Do not use severity to exaggerate uncertain findings.

# Final response

Start with a verdict:

- APPROVE
- REQUEST CHANGES
- COMMENT

Then list findings from highest to lowest severity.

For every finding include:

- severity
- affected file/location
- concrete problem
- why it matters
- expected correction

If no actionable problems are found, explicitly say so.

Also include:

## Issue coverage

State whether all acceptance criteria appear to be addressed.

## Scope

State whether the Pull Request stays within the linked Issue.

## Verification assessment

State whether the provided tests and verification appear sufficient.

Do not modify the Pull Request.
