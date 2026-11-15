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

First read the plugin's skills and mods for the command names.

1. `type "/<first letters of the name>" --session <session>`. Result: the driver prints `typed`,
   and the slash menu opens under the prompt.
2. `wait-for "<command name>" --session <session>`, then capture `screenshot`. Result: the menu,
   narrowed by the typed letters, lists the command, the driver prints `seen: <command name>`,
   and `screenshot` prints the `.png` path; with no such name by `stepMs`, `wait-for` exits 1.
3. `type --key Escape --session <session>`. Result: the driver prints `typed`, the prompt is
   cleared and the menu closes.
4. **Proof.** Result: the screenshot shows the plugin's command in the slash menu. Captures:
   screenshot

## Gotchas

- Wait for the prompt before typing `/`: a mod registers its commands as the session starts. Where
  a mod registers them: <https://code.claude.com/docs/en/plugins/mods/api#add-a-command-or-a-tool>.
