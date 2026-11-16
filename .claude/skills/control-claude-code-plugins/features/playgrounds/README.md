# playgrounds

The skills of `plugins/playgrounds`. Each one is driven with `<plugin-dir>` set to `plugins/playgrounds`.

## Parts

- `use`: Route playground requests to the first-party plugin, or install it, with recipes and guidance.

## Sub-features

none

## Entry points

- `/playgrounds:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/playgrounds:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `playgrounds` and
`<skill>` from Parts. The skill's own `plugins/playgrounds/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.
- The plugin declares a dependency on `playground` from `claude-plugins-official`
  (`plugins/playgrounds/.claude-plugin/plugin.json`). A local drive's session loads none of the
  person's installed plugins (its init event lists only the plugin under test and the built-in
  `cc-plugin-*` ones), so the dependency is unmet even where `playground` is installed and enabled:
  `plugin_errors` reports `dependency-unsatisfied`, Ready refuses because the plugin is not listed,
  and no entry point can be driven locally. Installing `playground` does not change this.
