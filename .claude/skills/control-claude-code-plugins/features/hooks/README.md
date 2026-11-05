# hooks

The hooks of a plugin under `plugins/<module>/hooks/`. Each one is driven with `<plugin-dir>` set to
`plugins/<module>`.

## Parts

- A hook runs on its event and its output shows in the session.
- A hook that blocks shows why it blocked.

## Sub-features

none

## Entry points

- A prompt that fires the hook's event, typed at the prompt of the terminal session | driven
- The same prompt as the `logs` prompt, in print mode | driven
- The same hook in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `hooks/output` feature.

## Drive

Drive the hook as the driving tool's `hooks/output` feature, with `<plugin-dir>` set to
`plugins/<module>`. The plugin's `hooks/hooks.json` gives the event and matcher, and its README gives
what the hook shows. Pick the module from the changed files.

## Gotchas

- The restricted launch removes Bash, so a hook on a Bash tool event never fires. Exercise the hook
  on an event a restricted session raises: session start, prompt submit, or a file-tool event. A
  hook that only matches Bash events: record the hook and its event as not driven here.
- Which tools the launch removes: the `--restricted` row of
  <https://code.claude.com/docs/en/cli-reference#cli-flags> (as of 2026-11-05; recheck when that row
  changes which tools it removes).
