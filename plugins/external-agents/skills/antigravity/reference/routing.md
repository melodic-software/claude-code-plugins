# Routing: model and effort

This skill holds no model names and no effort defaults. agy needs a model for every run: one the
user names for the run, or `antigravity.model` from config; with neither, the run is skipped. An
effort passes only when `antigravity.effort` is set. Which model and effort each agent role in a
multi-agent run uses is `/multi-agent:route`'s config, not this skill's.

agy's model slugs name a thinking level (for example a `-medium` suffix), and agy also takes
`--effort`. Which one wins when both are given is not documented; when the user sets both, say so
and suggest setting only the slug.

When the user asks which Gemini model or effort to use, or `update` prints `routing: due`, read the
sources below and answer from them, citing the section:

- The models this agy version offers: `models.txt` in the `cli facts:` folder from
  `external-agents update antigravity`.
- Index of the Antigravity CLI docs, to find a page that moved:
  [Get started](https://antigravity.google/docs/cli).
- Which models exist and how to pick one:
  [Choose a model § Choose a model](https://antigravity.google/docs/models/#choose-a-model) and
  [§ Reasoning model](https://antigravity.google/docs/models/#reasoning-model).
- Thinking levels and effort:
  [Choose a model § Select a model](https://antigravity.google/docs/models/#select-a-model) and
  [Effort command](https://antigravity.google/docs/cli/commands/effort).

A recommendation goes to the user as a config change for them to make (`antigravity.model`,
`antigravity.effort`), with the section it rests on. On `routing: due`, the check is the one in
[update.md § Routing refresh](update.md#routing-refresh).
