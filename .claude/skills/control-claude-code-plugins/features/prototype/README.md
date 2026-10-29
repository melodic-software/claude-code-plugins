# prototype

The skills of `plugins/prototype`. Each one is driven with `<plugin-dir>` set to `plugins/prototype`.

## Parts

- `build-generator`: Throwaway generating tool the person tunes, whose saved output goes into the project. No plain-words entry.
- `explore-directions`: Throwaway UI variations answering what should this look like. Its actions are `vary [<variant>]`, `combine [<base>]` and `controls [<variant>]`; any other first word is the scope.
- `pressure-test`: Throwaway terminal app or shareable HTML demo pressure-testing logic or a data model.

## Sub-features

none

## Entry points

- `/prototype:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/prototype:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `prototype` and
`<skill>` from Parts. The skill's own `plugins/prototype/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.
