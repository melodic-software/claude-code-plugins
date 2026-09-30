# Prompting Claude Opus 5.5

Excerpt of a real upstream page, kept for the attribution golden set. The passages below are copied
unchanged from the pages named next, and nothing else from them is reproduced.

Canonical location for the purposes of this case: `https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5`.

## Calibrate effort

[Effort](https://platform.claude.com/docs/en/build-with-claude/effort) is the main control for how much Claude Opus 5.5 thinks, and because thinking is always on, it's the first setting to adjust when trading off intelligence, latency, and cost. Start at `medium`, the default on Claude Opus 5.5 (Claude Opus 5 defaults to `high`), set it explicitly, and test several levels against your own evals rather than carrying over the setting you used on Claude Opus 5. Effort level names don't correspond to the same amount of thinking across models: in Anthropic's testing, Claude Opus 5.5 at `medium` matches or exceeds Claude Opus 5 at `high` on coding and knowledge-work evaluations, and on several coding evaluations `low` comes close to it at much lower cost. See [Recommended effort levels for Claude Opus 5.5](https://platform.claude.com/docs/en/build-with-claude/effort#recommended-effort-levels-for-claude-opus-5-5).

# Claude Code documentation: model configuration

Canonical location for the purposes of this case: `https://code.claude.com/docs/en/model-config`.

Opus 5.5 starts at `medium` unless one of the sources above sets a level for it, and a top-level `effortLevel` in your user settings file doesn't count for Opus 5.5. That key is the older form `/effort` wrote before Claude Code saved levels per model: it keeps applying where it applied before, on Opus 5, Fable 5.1, and earlier models, while Opus 5.5 and models released after it start at their own default until you choose a level for them with `/effort` or the `/model` picker. A top-level `effortLevel` in project, local, or managed settings, or one passed with `--settings`, applies to every model.
