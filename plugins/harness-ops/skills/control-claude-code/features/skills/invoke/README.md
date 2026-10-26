# Skill invocation

A skill from the plugin under test, run in a session.

## Parts

- The skill runs from its slash command with the arguments typed after it.
- The model picks the skill from a request in plain words, when the skill allows that.
- The skill's output lands in the transcript.

## Sub-features

none

## Entry points

- `/<plugin>:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- `/<plugin>:<skill> <args>` as the `log` prompt, in print mode | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

Undo what the skill wrote, the way its own SKILL.md says; a skill that only reports needs none.

## Drive

1. Read the skill's SKILL.md for its arguments and the text its output starts with.
2. `type "/<plugin>:<skill> <args>" --key Enter --session <session>`.
3. `wait-for "<text its output starts with>" --session <session>`, then capture `screenshot`.
4. For the plain-words entry point, type the request instead, and `wait-for` the same text.
5. Capture `logs` with the same slash command as the prompt.

## Gotchas

- A skill step that needs a tool the restricted launch removes stops there. Record the step and its
  entry point; never relaunch without the restriction. Which tools it removes: the `--restricted`
  row of <https://code.claude.com/docs/en/cli-reference#cli-flags> (as of 2026-10-26; recheck when
  that row changes which tools it removes).
- Wait on the skill's output, never on the slash command: the typed prompt shows in the transcript
  first.
