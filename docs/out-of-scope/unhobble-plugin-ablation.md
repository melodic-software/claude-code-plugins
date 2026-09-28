# Unhobble plugin ablation

Park for [#4095](https://github.com/melodic-software/claude-code-plugins/issues/4095).

## Decision

**Do not add a plugin classification pass or write `enabledPlugins: false`
overlays.** The mechanism exists. The missing piece is a rubric for skill-only
plugins, which this issue was going to define, and applying it would disable
marketplace plugins in the committed settings file. That is a product
classification, not a small patch. Parent campaign: #4094.

**Claim:** Project settings can set `enabledPlugins.<plugin>@<marketplace>` to
false, and that overrides a user-scope true. Using it as an unhobble strip
still needs a keep-versus-behavioral rubric this repo has not adopted for
skill-only plugins.
**Basis:** [Settings reference](https://code.claude.com/docs/en/settings-reference),
`enabledPlugins`, fetched 2026-09-28: "Project settings take precedence over
user settings." A managed `false` is a different lever (blocks installation).
`scripts/check-plugin-catalog-enablement.sh` already allows a recorded opt-out.
`docs/PLUGIN-PHILOSOPHY.md` classifies hooks, not skill-only plugins. #4090 is
the experiment that motivated the follow-up.
**As of:** 2026-09-28.
**Recheck:** An operator writes the skill-only rubric and names which plugins
are behavioral. Until then, do not commit a `false` overlay from this issue.

## What this close is not

Not a verification that `claude plugin list --json` shows a project `false`
as unloaded. The issue's own acceptance criteria still require that probe
before any arm is treated as stripped.
