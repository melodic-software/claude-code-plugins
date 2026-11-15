# Mod toast

A short notice a mod raises without starting a turn.

## Parts

- The toast appears with the mod's name and text, then goes.

## Sub-features

none

## Entry points

- The mod action that raises the toast, done in the terminal session | driven
- The same mod in Claude Desktop | not driven: terms

## Reset

None: a toast leaves no state of its own. Reset whatever the action that raised it saved, the way
the mod's README says.

## Drive

First read the mod's README for the action that raises a toast and its text (for
`plugins/context-budget`: `/context-budget nonsense` raises its usage line).

1. Capture `video` from before the action, so the toast is on record however briefly it shows.
   Result: `record start` prints `recording: <path>.mp4`.
2. `type "<command>" --key Enter --session <session>`. Result: the driver prints `typed`.
3. `wait-for "<toast text>" --session <session>`, then capture `screenshot`. Result: the toast
   shows the mod's name and that text, the driver prints `seen: <toast text>`, and `screenshot`
   prints the `.png` path; with no such text by `stepMs`, `wait-for` exits 1.
4. `record stop --session <session>`. Result: the driver prints `recording stopped` and writes
   the `.mp4` with a `.mp4.txt` holding every frame's text.
5. **Proof.** Result: the recording shows the toast with the mod's name and text appear, then go,
   with no turn started. Captures: video, screenshot

## Gotchas

- A toast is brief: start the recording before the action, never after.
- Close every pane before the action.
- What raises a toast and what holds it back:
  <https://code.claude.com/docs/en/plugins/mods/api#show-something-without-starting-a-turn> and
  <https://code.claude.com/docs/en/plugins/mods/interface#hold-toasts-behind-a-dialog>.
