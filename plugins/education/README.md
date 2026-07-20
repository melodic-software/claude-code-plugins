# education

A Claude Code plugin that coaches you through learning a subject — across
multiple sessions — instead of lecturing at you. It runs a
**Knowledge → Skills → Wisdom** progression grounded in your real goal, and keeps
persistent per-topic learning state so each session builds on the last.

Invoke `/education:teach` with an action for coached, multi-session learning, for
example `/education:teach topic rust-ownership`,
`/education:teach codebase auth-flow`, or `/education:teach primer color-grading`.
For a one-shot plain-language explanation, invoke `/education:explain` — or just
say "I don't get it" and let it auto-invoke.

## What it does

`teach` is the multi-session coach; `explain` is its one-shot sibling.

- **`/education:teach topic <subject>`** — learn a general subject from external
  high-trust sources (books, courses, docs, communities).
- **`/education:teach codebase <concept>`** — learn a concept grounded in the
  repository you launch it from. It discovers the repo's own docs, conventions,
  and source at teach-time and teaches from what it finds — nothing about the
  project is assumed.
- **`/education:teach primer <domain>`** — a single-session vocabulary primer for
  an unfamiliar domain, so you can prompt or direct work in it precisely. No
  workspace.
- **`/education:explain [thing]`** — a one-shot, plain-language explainer. It
  drops any concept, code, error, architecture, or the previous assistant
  response to genuinely plain words (concrete analogy, zero jargon), then layers
  altitude up only on request (high-school, then peer level). An empty argument
  explains the previous assistant response, so "I don't get it" needs no topic.
  It closes by offering `/education:teach` when you want ongoing coaching rather
  than a single explanation.
- Supporting `teach` actions: `mission`, `glossary`, `resources`, `explain`,
  `exercise`, `assess`, `resume`, `status`.

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

- **Bash + coreutils** (`sha256sum`/`shasum`, `realpath`, `tr`, `sed`) for the
  skill's inline mechanics — on native Windows, install
  [Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows) so
  they run under Git Bash, which bundles all of them.
- For `codebase` mode, launch it from the repository you want to learn — the
  plugin reads that repo's own docs and source.
- `topic` mode fetches documentation URLs to ground explanations in primary
  sources; if your setup restricts `WebFetch`, allow it or seed `RESOURCES.md`
  manually.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install education@melodic-software
```

## Configuration

This plugin has no `userConfig`. Everything it needs comes from the action you
invoke, and its cross-session learning state persists automatically under
`${CLAUDE_PLUGIN_DATA}`. There is nothing to configure and nothing to edit in the
plugin itself.

## License

MIT (SPDX-License-Identifier: MIT).
