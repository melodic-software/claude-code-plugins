# Routing: model and effort

This skill holds no model names and no effort defaults; without an override agy's own default
runs. Which vendor, model and effort fit a task is `/multi-agent:route vendors <task>`'s choice,
made on criteria and benchmarks shared across vendors. This file lists only agy's own facts and
docs.

agy's model slugs name a thinking level (for example a `-medium` suffix), and agy also takes
`--effort`. Which one wins when both are given is not documented; when the user sets both, say so
and suggest setting only the slug.

When the user asks which Gemini model or effort to use, or `update` prints `routing: due`, read the
sources below and answer from them, citing the section:

- The models and effort levels this agy version offers: `external-agents models antigravity` (JSON).
- Index of the Antigravity CLI docs, to find a page that moved:
  [Get started](https://antigravity.google/docs/cli).
- Which models exist and how to pick one:
  [Choose a model § Choose a model](https://antigravity.google/docs/models/#choose-a-model) and
  [§ Reasoning model](https://antigravity.google/docs/models/#reasoning-model).
- Thinking levels and effort:
  [Choose a model § Select a model](https://antigravity.google/docs/models/#select-a-model) and
  [Effort command § Inspect or override effort in headless mode](https://antigravity.google/docs/cli/commands/effort#inspect-or-override-effort-in-headless-mode).

A recommendation goes to the user as a config change for them to make (`antigravity.model`,
`antigravity.effort`), with the section it rests on. On `routing: due`, the check is the one in
[update.md § Routing refresh](update.md#routing-refresh).
