# teach

A Claude Code plugin that coaches you through learning a subject — across
multiple sessions — instead of lecturing at you. It runs a
**Knowledge → Skills → Wisdom** progression grounded in your real goal, and keeps
persistent per-topic learning state so each session builds on the last.

Invoke it with `/teach:teach` and an action, for example
`/teach:teach topic rust-ownership`, `/teach:teach codebase auth-flow`, or
`/teach:teach primer color-grading`.

## What it does

- **`topic <subject>`** — learn a general subject from external high-trust
  sources (books, courses, docs, communities).
- **`codebase <concept>`** — learn a concept grounded in the repository you launch
  it from. It discovers the repo's own docs, conventions, and source at teach-time
  and teaches from what it finds — nothing about the project is assumed.
- **`primer <domain>`** — a single-session vocabulary primer for an unfamiliar
  domain, so you can prompt or direct work in it precisely. No workspace.
- Supporting actions: `mission`, `glossary`, `resources`, `explain`, `exercise`,
  `assess`, `resume`, `status`.

The coach asks questions before giving answers, teaches just beyond your current
level (the zone of proximal development), and grounds every claim in a source
fetched or a file read that session rather than from memory.

## How it works

Each topic gets a **workspace** — a mission (why you're learning this), a glossary,
curated resources, and per-concept slices (a lesson, a durable reference
cheat-sheet, and optional practice). All of it persists under
`${CLAUDE_PLUGIN_DATA}`, which survives plugin updates and stays out of your
project's tree, so you can resume a topic weeks later. Durable references are
re-verified lazily on revisit (age × domain-velocity) so stale facts get refreshed
before they're taught. See the skill body for the full pedagogy.

## Requirements

- None beyond Claude Code. For `codebase` mode, launch it from the repository you
  want to learn — the plugin reads that repo's own docs and source.
- `topic` mode fetches documentation URLs to ground explanations in primary
  sources; if your setup restricts `WebFetch`, allow it or seed `RESOURCES.md`
  manually.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install teach@melodic-software
```

## Configuration

This plugin has no `userConfig`. Everything it needs comes from the action you
invoke, and its cross-session learning state persists automatically under
`${CLAUDE_PLUGIN_DATA}`. There is nothing to configure and nothing to edit in the
plugin itself.

## License

MIT (SPDX-License-Identifier: MIT). See the LICENSE file at the root of the
melodic-software/claude-code-plugins repository.
