# Permission dialog

The dialog Claude Code shows when a tool call needs the person's approval.

## Parts

- A tool call that needs approval waits on a dialog.
- Answering No refuses the call.
- Answering Yes runs the call.

## Sub-features

none

## Entry points

- A prompt that leads to a file write in the working directory, answered No | driven
- The same prompt, answered Yes | not driven: writes into the person's working directory
- The same dialog in Claude Desktop | not driven: terms

## Reset

When `ccprobe.txt` exists in the working directory after the run, something approved the write:
record that, then delete the file.

## Drive

1. Capture `video` from before the prompt.
2. `type "Write the word ok into a new file in this directory, named by joining ccprobe, a dot and txt." --key Enter --session <session>`.
3. `wait-for "<dialog text>" --session <session>`, with the dialog's wording from this feature's
   Gotchas, then capture `screenshot`. Until a Gotcha records the wording, read it from the video
   instead, and hand it on as a lesson for this feature.
4. `type --key Escape --session <session>` to answer No, and capture `screenshot`.
5. `record stop --session <session>`, then check Reset.

## Gotchas

- Never wait on `ccprobe.txt` alone: Claude's reply can name the file before the dialog draws. The
  prompt spells the name in parts so the full name comes only from Claude.
- When no dialog shows, look for a managed setting or a hook of the plugin under test that approves
  the write before recording the dialog as missing; the restricted launch loads only managed
  settings and `--settings`, per the `--restricted` row of
  <https://code.claude.com/docs/en/cli-reference#cli-flags> (as of 2026-10-26; recheck when that
  row changes which settings it loads).
