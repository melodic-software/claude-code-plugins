# mods

The mods a plugin registers in `plugins/<module>/hooks/register.tsx`. Each one is driven with
`<plugin-dir>` set to `plugins/<module>`.

## Parts

- The mod's band, toast or panel shows its content once the mod has something to draw.
- The mod's command, when it registers one, changes what the mod draws.

## Sub-features

none

## Entry points

- The mod's command, typed at the prompt of the terminal session | driven
- The same mod in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `mods/band`, `mods/toast` or `mods/panel` feature, whichever
the mod draws in.

## Drive

Read `register.tsx` for where the mod draws, then drive it as the driving tool's `mods/band`,
`mods/toast` or `mods/panel` feature, with `<plugin-dir>` set to `plugins/<module>`. A mod that draws
in more than one place gets one pass per place.

## Gotchas

- A change to `register.tsx` also matches the `hooks` feature, which lists every file under
  `plugins/*/hooks/`: drive both when both are listed.
- Load only the plugin under test, so a screenshot shows its content alone.
