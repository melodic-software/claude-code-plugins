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

First read the mod's README for the command that opens its pane, the text the pane shows, its keys
and its close action (for `plugins/context-budget`: `/context-budget live pane`).

1. `type "<command>" --key Enter --session <session>`. Result: the driver prints `typed`.
2. `wait-for "<text the pane shows>" --session <session>`, then capture `screenshot`. Result: the
   pane is open with the mod's title and that text, the driver prints `seen: <text the pane
   shows>`, and `screenshot` prints the `.png` path, its `.png.txt` holding the pane's text; with
   no such text by `stepMs`, `wait-for` exits 1.
3. For each key the README names, `type --key <Name> --session <session>`, `wait-for` its result,
   and capture `screenshot`. Result: the pane shows what the README says that key shows, and the
   driver prints `seen: <that text>`.
4. Close the pane with the README's close action. Result: the pane and its text are gone from the
   screen.
5. **Proof.** Result: the pane is closed and the transcript and prompt show without it; the step 2
   and 3 screenshots show it open with the mod's title and content, then changed by each key.
   Captures: screenshot

## Gotchas

- The driver's terminal is 120 columns wide, so open a pane with the mod's command rather than
  waiting for the mod to open it.
- Where a pane sits and when it waits for a wider terminal:
  <https://code.claude.com/docs/en/plugins/mods/interface#open-a-pane-at-the-right-time>.
