# Hook output

What a hook of the plugin under test shows when its event fires.

## Parts

- The hook runs on its event and its output shows in the session.
- A hook that blocks shows why it blocked.

## Sub-features

none

## Entry points

- A prompt that fires the hook's event, typed at the prompt of the terminal session | driven
- The same prompt as the `log` prompt, in print mode | driven
- The same hook in Claude Desktop | not driven: terms

## Reset

Undo what the hook wrote, the way the plugin's README says; a hook that only reports needs none.

## Drive

1. Read the plugin's `hooks/hooks.json` for the event and matcher, and its README for what the hook
   shows.
2. `type "<a prompt that fires the event>" --key Enter --session <session>`.
3. `wait-for "<text the hook shows>" --session <session>`, then capture `screenshot`.
4. Capture `logs` with the same prompt.

## Gotchas

- Fire the hook through a tool the restricted launch keeps, such as a file read in the working
  directory. Which tools it removes: the `--restricted` row of
  <https://code.claude.com/docs/en/cli-reference#cli-flags> (as of 2026-10-26; recheck when that
  row changes which tools it removes).
- Never wait on text the prompt itself holds: the typed prompt shows in the transcript first.
