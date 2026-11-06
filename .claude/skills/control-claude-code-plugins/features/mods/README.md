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

A mod that transforms transcript components has no band, toast or panel:

1. Read `register.ts` or `register.tsx` for the components it handles (assistant message, user
   message, tool use, tool result).
2. `type "<a prompt that makes one of them appear>" --key Enter --session <session>`, choosing a
   prompt whose result holds the text the mod changes.
3. `wait-for "<text the mod shows in place of the original>" --session <session>`, then capture
   `screenshot`. One pass per component the change touches.

## Gotchas

- A change to a `.ts` or `.tsx` file under `hooks/` also matches the `hooks` feature, which lists
  every file under `plugins/*/hooks/`: drive both when both are listed.
- Load only the plugin under test, so a screenshot shows its content alone.
- Never wait on text the prompt itself holds: the typed prompt shows in the transcript first.
