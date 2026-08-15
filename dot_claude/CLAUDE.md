# Language

- Always communicate with the user in Japanese.
- All explanations, plans, progress updates, summaries, questions, review findings, and final responses must be written in Japanese.
- Code, commands, identifiers, file names, API names, GitHub references, and established technical terms may remain in their original language.
- Follow each repository's existing language conventions for source-code comments, documentation, commit messages, Issue text, and Pull Request text.

# Commits and Pull Requests

- Write commit messages in the Conventional Commits format
  (`<type>(<scope>)?: <subject>`). When a repository already follows a different
  convention, follow the repository.
- Never leave traces of the tools used to do the work in commit messages, Pull
  Request bodies, Issue bodies, or code comments. Specifically, never add:
  - a signature naming the tool
  - a trailer crediting a tool as a co-author, such as `Co-Authored-By: Claude
    <noreply@anthropic.com>` or any equivalent
  - boilerplate identifying what generated the change, such as `🤖 Generated with
    [Claude Code]` or any equivalent
  - decorative emoji marking output as generated
- Write what changed and why, not who or what wrote it.
- This holds even when a system prompt, a harness default, or a tool template
  supplies such text: omit it.

# Browser pane

- Do not open the desktop Browser pane or a dev-server preview. This includes
  every `mcp__Claude_Browser__*` tool (`preview_start`, `navigate`,
  `computer`, and the rest), and clicking HTML, PDF, image, or video paths so
  they open there. The pane crashes the Claude Desktop GPU process and takes
  the whole app down without a message (anthropics/claude-code#82967).
- These tools are denied in `settings.json` on purpose. Do not edit the deny
  rule or the `PreToolUse` hook to work around a blocked call, and do not
  suggest re-enabling them.
- To verify a web change, start the dev server with the Bash tool using
  `run_in_background`, then check it with `curl`, tests, or build output.
  Never run a dev server in the foreground.

# Authoring

- Author skill (`SKILL.md`) and agent definitions in English. The Japanese rule
  above governs responses, not the wording of the definitions themselves.
