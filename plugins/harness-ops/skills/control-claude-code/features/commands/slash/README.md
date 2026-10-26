# Slash commands

The commands the plugin under test adds to the slash menu, from its skills and its mods.

## Parts

- Typing `/` lists the plugin's commands beside the built-in ones.
- Typing more of a name narrows the list.
- Choosing a command runs it.

## Sub-features

- Running a skill command: [skill invocation](../../skills/invoke/README.md)

## Entry points

- `/` and part of the command's name, typed at the prompt of the terminal session | driven
- The command's full name and Enter, typed at the prompt | driven
- The same commands in Claude Desktop | not driven: terms

## Reset

None: the menu keeps no state. Clear the prompt with `type --key Escape --session <session>`.

## Drive

1. Read the plugin's skills and mods for the command names.
2. `type "/<first letters of the name>" --session <session>`.
3. `wait-for "<command name>" --session <session>`, then capture `screenshot`.
4. `type --key Escape --session <session>`.

## Gotchas

- Wait for the prompt before typing `/`: a mod registers its commands as the session starts. Where
  a mod registers them: <https://code.claude.com/docs/en/plugins/mods/api#add-a-command-or-a-tool>
  (as of 2026-10-26; recheck when that section changes when registered commands appear).
