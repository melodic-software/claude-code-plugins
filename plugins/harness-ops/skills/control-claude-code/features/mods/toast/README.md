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

1. Read the mod's README for the action that raises a toast and its text (for
   `plugins/context-budget`: `/context-budget nonsense` raises its usage line).
2. Capture `video` from before the action, so the toast is on record however briefly it shows.
3. `type "<command>" --key Enter --session <session>`.
4. `wait-for "<toast text>" --session <session>`, then capture `screenshot`.
5. `record stop --session <session>`.

## Gotchas

- A toast is brief: start the recording before the action, never after.
- An open pane can hold toasts back; close every pane before the action.
- What raises a toast and what holds it back:
  <https://code.claude.com/docs/en/plugins/mods/api#show-something-without-starting-a-turn> and
  <https://code.claude.com/docs/en/plugins/mods/interface#hold-toasts-behind-a-dialog> (as of
  2026-10-26; recheck when either section changes how long a toast shows or what holds it).
