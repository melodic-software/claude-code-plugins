# Mod panel

A pane a mod opens: a sidebar beside the transcript, or a region above the prompt.

## Parts

- The pane opens with the mod's title and content.
- Keys or buttons in the pane change what it shows.
- The pane closes on the mod's close action.

## Sub-features

none

## Entry points

- The mod's command, typed at the prompt of the terminal session | driven
- The same mod in Claude Desktop | not driven: terms

## Reset

Close the pane, then return what the mod saved to its default the way the mod's README says.

## Drive

1. Read the mod's README for the command that opens its pane and the text the pane shows (for
   `plugins/context-budget`: `/context-budget live pane`).
2. `type "<command>" --key Enter --session <session>`.
3. `wait-for "<text the pane shows>" --session <session>`, then capture `screenshot`.
4. For each key the README names, `type --key <Name> --session <session>`, `wait-for` its result,
   and capture `screenshot`.
5. Close the pane with the README's close action.

## Gotchas

- The driver's terminal is 120 columns wide. A pane the mod opens on its own can wait for a wider
  terminal and never show; open it with the mod's command.
- Where a pane sits and when it waits for a wider terminal:
  <https://code.claude.com/docs/en/plugins/mods/interface#open-a-pane-at-the-right-time> (as of
  2026-10-26; recheck when that section changes the widths).
