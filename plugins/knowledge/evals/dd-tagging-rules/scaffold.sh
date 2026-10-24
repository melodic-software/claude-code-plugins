#!/usr/bin/env bash
# Seed an invented vendor blog post with eight claim rows and two small docs
# corpora, each with a page index. Each index lists one page this script does
# not create (harness: workspaces.md, platform: citations.md). Line numbers in
# the corpus pages are fixed: graders cite skill-folders.md:5, delegates.md:5,
# prompting.md:5 and event-hooks.md:9.
set -euo pipefail

mkdir -p source corpus/harness corpus/platform

cat >source/blog-post.md <<'MD'
# Field notes on agent setups

- URL: https://claude.com/blog/field-notes-on-agent-setups
- Published: 2026-10-14
- Fetched: 2026-10-20

## Claim rows

R1. Store each skill in its own folder with a SKILL.md file at its root, and keep a CHANGELOG.md beside it so reviewers can see what changed.
R2. An output checklist at the end of a prompt cuts revision rounds in half.
R3. Organize subagents in three tiers: one planner at the top, one reviewer per code area, and workers under each reviewer.
R4. Add a PostToolUse hook that runs your license-header check after every file edit.
R5. Every subagent inherits the main session's full conversation history.
R6. Place long reference documents above your question in the prompt.
R7. Turn verbosity down for routine edits to get shorter answers.
R8. Hooks receive the event as JSON on stdin.
MD

cat >corpus/harness/llms.txt <<'MD'
# Claude Code docs index

- [Skills](skill-folders.md)
- [Subagents](delegates.md)
- [Hooks](event-hooks.md)
- [Settings](config-keys.md)
- [Workspaces](workspaces.md)
MD

cat >corpus/harness/skill-folders.md <<'MD'
# Skills

A skill is a folder of instructions Claude loads when a task needs it.

Store each skill in its own folder with a SKILL.md file at its root.

Claude reads each skill's description at startup to decide when to use it.

Keep SKILL.md focused, and move long reference material into separate files.
MD

cat >corpus/harness/delegates.md <<'MD'
# Subagents

A subagent is a separate Claude instance the main session delegates a task to.

Each subagent starts in a fresh context window and does not see the main conversation.

Define a subagent as a Markdown file with a name, a description and a tool list.

The main session receives only the subagent's final message.
MD

cat >corpus/harness/event-hooks.md <<'MD'
# Hooks

Hooks are shell commands Claude Code runs at fixed points in a session.

A PostToolUse hook runs after a tool call completes.

A common use is running a formatter after each file edit.

Hooks receive the event as JSON on stdin.
MD

cat >corpus/harness/config-keys.md <<'MD'
# Settings

Settings live in settings.json at user, project or local scope.

`verbosity`: how long Claude's replies are, `low`, `medium` or `high`.

Turn verbosity down to `low` for routine edits to get shorter replies.
MD

cat >corpus/platform/llms.txt <<'MD'
# Platform docs index

- [Prompting guide](prompting.md)
- [Verbosity](verbosity.md)
- [Citations](citations.md)
MD

cat >corpus/platform/prompting.md <<'MD'
# Prompting guide

Give the model clear, direct instructions.

Place long reference documents at the top of the prompt, above your question.

An output checklist at the end of a prompt helps the model confirm each requirement before it answers.

For the Nimbus model family, put the question first: documents above the question lower recall.
MD

cat >corpus/platform/verbosity.md <<'MD'
# Verbosity

The `verbosity` request parameter sets response length: `low`, `medium` or `high`.

For batch jobs, set `verbosity` to `low` in the request body.

Lower verbosity shortens responses and reduces output tokens.
MD
