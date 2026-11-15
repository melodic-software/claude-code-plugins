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

1. Capture `video` from before the prompt. Result: `record start` prints `recording: <path>.mp4`.
2. `type "Write the word ok into a new file in this directory, named by joining ccprobe, a dot and txt." --key Enter --session <session>`.
   Result: the driver prints `typed`.
3. `wait-for "<dialog text>" --session <session>`, with the dialog's wording from this feature's
   Gotchas, then capture `screenshot`. Until a Gotcha records the wording, read it from the video
   instead, and hand it on as a lesson for this feature. Result: the permission dialog asks to
   approve the write, the driver prints `seen: <dialog text>`, and `screenshot` prints the `.png`
   path; with no such text by `stepMs`, `wait-for` exits 1.
4. `type --key Escape --session <session>` to answer No, and capture `screenshot`. Result: the
   dialog is gone and the write is refused.
5. `record stop --session <session>`, then check Reset. Result: the driver prints
   `recording stopped`, and no `ccprobe.txt` exists in the working directory.
6. **Proof.** Result: the dialog showed for the write and, answered No, left no `ccprobe.txt`
   behind. Captures: video, screenshot

## Gotchas

- Never wait on `ccprobe.txt` alone: Claude's reply can name the file before the dialog draws. The
  prompt spells the name in parts so the full name comes only from Claude.
- When no dialog shows, look for a managed setting or a hook of the plugin under test that approves
  the write before recording the dialog as missing; which settings the restricted launch loads is
  read live from the `--restricted` row of
  <https://code.claude.com/docs/en/cli-reference#cli-flags>.
