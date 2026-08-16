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

# Messages that arrive mid-turn

- A message the user sends while work is in progress is delivered inside the
  running turn, alongside a tool result, prefixed with `The user sent a new
  message while you were working:`. Treat it exactly like a message that started
  a turn. It is not ambient context.
- If it is a question, answer it in text before the next tool call. If answering
  needs investigation, investigate and answer in the first text after that, then
  return to the original work. Never defer the answer to the end of the turn.
- Never substitute a code or config change for an answer. A question is
  something to answer, not a work instruction. If a change is also warranted,
  answer first, then say what will be changed.
- If it is an instruction or a change of direction, state in one or two lines
  what will change before continuing. Do not absorb it silently.
- Before ending a turn, check that no mid-turn message is left unanswered. If
  one is, answer it at the top of the final response.

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
