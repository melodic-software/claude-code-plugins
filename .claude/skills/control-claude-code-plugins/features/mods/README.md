# mods

The mods a plugin registers in `plugins/<module>/hooks/register.ts` or `register.tsx`, and the
`.ts` and `.tsx` files beside it that it imports. Each one is driven with `<plugin-dir>` set to
`plugins/<module>`.

## Parts

- The mod's band, toast or panel shows its content once the mod has something to draw.
- A mod that transforms transcript components shows the transformed component in the transcript.
- The mod's command, when it registers one, changes what the mod draws.

## Sub-features

none

## Entry points

- The mod's command, typed at the prompt of the terminal session | driven
- A prompt that makes a component the mod transforms appear in the transcript, typed at the prompt | driven
- The same mod in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `mods/band`, `mods/toast` or `mods/panel` feature, whichever
the mod draws in. A transcript transform needs none.

## Drive

Read the mod's `register.ts` or `register.tsx` for where it draws, then drive it as the driving
tool's `mods/band`, `mods/toast` or `mods/panel` feature, with `<plugin-dir>` set to
`plugins/<module>`. A mod that draws in more than one place gets one pass per place.

A mod that draws nothing of its own (it forwards other mods' toasts, logs, or runs scripts on
events) has nothing to wait for here: record it as `not driven: draws nothing` and drive it as the
`hooks` feature, which its files also match.

A mod that transforms transcript components has no band, toast or panel. First read
`register.ts` or `register.tsx` for the components it handles (assistant message, user message,
command output, tool use, tool result, question, info notice), then, once per component the change
touches:

1. `type "<a prompt that makes one of them appear>" --key Enter --session <session>`, choosing a
   prompt whose result holds the text the mod changes. Result: the driver prints `typed`.
2. `wait-for "<text the mod shows in place of the original>" --session <session>`, then capture
   `screenshot`. Result: the component shows the mod's text in place of the original, the driver
   prints `seen: <that text>`, and `screenshot` prints the `.png` path; with no such text by
   `stepMs`, `wait-for` exits 1.
3. **Proof.** Result: the transcript shows each touched component with the mod's text in place of
   the original. Captures: screenshot

## Gotchas

- A change to a `.ts` or `.tsx` file under `hooks/` also matches the `hooks` feature, which lists
  every file under `plugins/*/hooks/`: drive both when both are listed.
- Load only the plugin under test, so a screenshot shows its content alone.
- Never wait on text the prompt itself holds: the typed prompt shows in the transcript first.
- A toast can be gone before the next `screenshot`: capture `video` around the step that raises it,
  as the `mods/toast` feature does.
- display-redaction's default block style keeps the masked text and recolors it, so step 2 has no
  new text to wait on there. Wait on `[hidden]`, which it draws for tool use, tool result, question
  and info notice components, or run with `mask_style` set to `text`.
