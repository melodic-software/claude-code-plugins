# education

A Claude Code plugin that coaches you through learning a subject — across
multiple sessions — instead of lecturing at you. It runs a
**Knowledge → Skills → Wisdom** progression grounded in your real goal, and keeps
persistent per-topic learning state so each session builds on the last.

Invoke `/education:teach` with an action for coached, multi-session learning, for
example `/education:teach topic rust-ownership`,
`/education:teach codebase auth-flow`, or `/education:teach primer color-grading`.
For a one-shot plain-language explanation, invoke `/education:explain` — or just
say "I don't get it" and let it auto-invoke. After Claude finishes a change,
invoke `/education:quiz-me` to be quizzed on what was done.

## What it does

`teach` is the multi-session coach; `explain` is its one-shot sibling; `quiz-me`
verifies you absorbed a completed change.

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
- **`/education:quiz-me`** — a post-work comprehension check. After a change is
  complete, it generates a self-contained HTML report of what was done (context,
  intuition, decisions) with a quiz at the bottom you answer — verifying that
  *you* absorbed the work, not just that the artifact is correct. It is
  non-gating by default; the `quiz_policy` setting tunes how often a quiz is
  offered. Its `recall <query>` action answers "what did we do on `<ticket>`" from
  a retained report library first, git and tracker history second.
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

`teach` and `explain` need no configuration; their state persists automatically
under `${CLAUDE_PLUGIN_DATA}`. `quiz-me` adds two optional settings, both with
defaults that preserve zero-config behavior:

| Setting | Type | Default | What it does |
| --- | --- | --- | --- |
| `quiz_policy` | string | `on-request` | When `quiz-me` offers a quiz: `off` (never), `on-request` (only when asked), `always` (after each completed change), `above-threshold` (when the change is large). Offer cadence only — a report is never generated without your confirmation. Unknown values act as `on-request`. |
| `report_library_dir` | directory | *(unset)* | Where `quiz-me` stores reports. Unset uses the plugin's own `${CLAUDE_PLUGIN_DATA}`; set it to a corpus checkout to redirect the library root there. Reports never land in the repo you are working in. |

Configure them through the `/plugin` dialog, or headless at install time with
`claude plugin install --config quiz_policy=always`. A literal non-home
`report_library_dir` may be rejected by hardcoded-path guardrails until the
shared library-path indirection (issue #798) lands.

## License

MIT (SPDX-License-Identifier: MIT).
