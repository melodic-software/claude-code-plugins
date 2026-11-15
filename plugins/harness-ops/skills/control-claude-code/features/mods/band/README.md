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

First read the mod's README for the command that turns its band on, the text the band shows, and
whether it draws only after a response (for `plugins/context-budget`: `/context-budget live band`,
which draws nothing before the first response).

1. When it draws only after a response, first `type "Reply with the number after 41, digits only." --key Enter --session <session>`
   and `wait-for "42" --session <session>`; the prompt never holds the reply's text. Result: the
   driver prints `typed`, then `seen: 42` once the reply shows in the transcript.
2. `type "<command>" --key Enter --session <session>`. Result: the driver prints `typed`.
3. `wait-for "<text the band shows>" --session <session>`. Result: the band above the prompt shows
   the text and the driver prints `seen: <text the band shows>`; with no such text by `stepMs` it
   exits 1.
4. Capture `screenshot`; for a band that changes over a turn, capture `video` around one prompt.
   Result: `screenshot` prints the `.png` path and writes it with a `.png.txt` sidecar holding the
   band's text; `record stop` prints `recording stopped` and writes the `.mp4.txt` frame text.
5. **Proof.** Result: the band above the prompt shows the README's text, and no other mod's
   content. Captures: screenshot, video for a band that changes over a turn

## Gotchas

- Every loaded mod can draw in the band. Load only the plugin under test, so a screenshot shows its
  content alone.
- Where the band is and how mods share it:
  <https://code.claude.com/docs/en/plugins/mods/interface#pick-where-to-draw>.
