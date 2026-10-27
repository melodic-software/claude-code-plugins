# Mod band

What a mod draws in the band, the strip above the prompt that every mod shares.

## Parts

- The band shows the mod's content once the mod has something to draw.
- The band changes when the mod's state changes, and empties when the mod draws nothing.

## Sub-features

none

## Entry points

- The mod's command, typed at the prompt of the terminal session | driven
- The same mod in Claude Desktop | not driven: terms

## Reset

Return what the mod saved to its default the way the mod's README says. A relaunch alone may keep
saved values.

## Drive

1. Read the mod's README for the command that turns its band on, the text the band shows, and
   whether it draws only after a response (for `plugins/context-budget`: `/context-budget live
   band`, which draws nothing before the first response).
2. When it draws only after a response, first `type "Reply with the number after 41, digits only." --key Enter --session <session>`
   and `wait-for "42" --session <session>`; the prompt never holds the reply's text.
3. `type "<command>" --key Enter --session <session>`.
4. `wait-for "<text the band shows>" --session <session>`.
5. Capture `screenshot`; for a band that changes over a turn, capture `video` around one prompt.

## Gotchas

- Every loaded mod can draw in the band. Load only the plugin under test, so a screenshot shows its
  content alone.
- Where the band is and how mods share it:
  <https://code.claude.com/docs/en/plugins/mods/interface#pick-where-to-draw> (as of 2026-10-26;
  recheck when that section changes where the band draws).
