# Command results as evidence

Detail behind the deviations-log evidence rule in [SKILL.md](../SKILL.md) and the evidence rule in
the `phase-verifier` agent. It is guidance only. This plugin ships no logging hook.

## What counts

A claim that a command ran and what it returned ("tests pass", "build green", "lint clean") is
evidence only when the harness recorded the run. In order of preference:

1. **A run the citing agent made itself.** The orchestrator's main-side build/test gate and the
   verifier's own read-only checks come back as tool results the harness wrote. Cite the command
   and its result, not a summary of it.
2. **A harness- or hook-written record of someone else's run**, such as a log a consuming project's
   hook appends per Bash call, or a transcript tool result matched by its tool-use id. Cite the
   entry.
3. **Never a worker's return prose, a `DEVIATIONS.md` line, or the orchestrator's own memory of a
   run.** These are claims. Promote them by re-running the command (1) or finding the record (2),
   or mark the entry `unverified`.

Basis: Anthropic's Claude Code best-practices page asks for the command run and what it returned
rather than an assertion of success; the oracle-independence research slice behind this plugin's
2026-10-06 change found no artifact in this pipeline written by the harness rather than the agent.

## Before relying on a hook-written log

A project that wants item 2 as a hook must probe the hook input first. As of 2026-10-06 the hooks
reference documents Bash tool output as `stdout`, `stderr`, `interrupted` and `isImage`, with no
exit-code field, and documents PostToolUseFailure for a tool that started executing and failed; its
example shows `npm test` with "Exit code 1". Whether every non-zero Bash exit reaches
PostToolUseFailure, and in what shape, was not probed. Run a deliberate failing command with a
logging hook on both PostToolUse and PostToolUseFailure and read what arrives before keying a log or
a Stop gate on exit status. A log keyed on a field that never arrives records every run as green.

- **Pointer**: the PostToolUse and PostToolUseFailure sections of the
  [hooks reference](https://code.claude.com/docs/en/hooks), and the verification guidance in
  [best practices](https://code.claude.com/docs/en/best-practices).
- **As of**: 2026-10-06.
- **Recheck trigger**: the hooks reference adds an exit-code field to Bash tool output, changes
  when PostToolUseFailure fires, or a probe in a consuming project shows a non-zero exit arriving
  differently than documented.
