# themes

A home for backdrop themes for the Claude Code desktop app. Each theme lives in its own folder
under `hooks/`.

The first theme is bedroom: a teenager's bedroom in the country at dusk, about 2004. More bedrooms,
one per decade, are planned.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install themes@melodic-software
/plugin enable themes
```

The catalog entry sets `defaultEnabled: false`, because the backdrop takes over the whole window;
`/plugin enable themes` turns it on. `/bedroom off` clears the theme for the session.

## Requirements

- The Claude Code desktop app. The mod draws only on the desktop surface; a terminal session loads
  it and draws nothing.
- Claude Code 2.1.287 or later, the floor for mods. `claude plugin validate` and
  `claude plugin test` pass on 2.1.328.

## Bedroom

A window with blinds onto the sky, a dresser with a television, VCR, game console and lava lamp, a
desk with a computer and lamp, posters, a pennant and a cat lying on the television. The room is
one SVG; a lighting shader over it runs at 30 frames a second and draws what each switch changes,
so a click changes the room without sending it again.

### What you can click

The television, the VCR (or the tape standing beside the console), the console, the
computer, the ceiling light switch by the door, the desk lamp and the lava lamp each switch on or
off. The cat purrs. If clicks land in the wrong place, run `/bedroom calibrate` and click the
bottom-left corner of the front of the dresser.

### The settings card

`/bedroom` alone shows a card in the conversation, so you need not know the words. It is five rows,
so it fits without scrolling: the theme on or off, reset, calibrate and Close; a button for each
switch showing whether it is on; dim, glass and blur steps side by side; and the four title fields,
two to a row (Enter sets one; empty puts the default back). Each button runs the same `/bedroom`
command you would type, so it costs what that command costs: a switch changes in the shader without
the room being sent again. A switch's button draws dim, with `…` after its state, until the switch
has finished changing, about a second (three for the console, which boots), and a press on it
meanwhile does nothing; clicks in the room are never held back. The card follows changes made by
clicks in the room and by typed commands. Close puts it away; `/bedroom` shows it again at the end
of the conversation. Away from the desktop app, `/bedroom` answers in text alone.

### Dim and titles

Dim is a dark veil laid over the whole room, so a dim step changes the veil alone and the room keeps
moving. The titles are drawn into the room itself, so changing one sends the room again. The room
then shows as it stands, ceiling light off included, for seven seconds while the app takes the new
room, and the shader takes it over again after that: the lights, screens and clock move again, and
clicks are answered at once. A click in those seven seconds still counts and is drawn into the room.

### The `/bedroom` command

| Command | Does |
|---|---|
| `/bedroom` | Says what is on and off; in the desktop app, also shows the settings card |
| `/bedroom status` | Says what is on and off |
| `/bedroom <tv\|tape\|console\|pc\|light\|lamp\|lava> [on\|off]` | Switches one thing; with neither word it flips |
| `/bedroom dim <0-80>` | Lays a dark veil over the room |
| `/bedroom glass <0-95>`, `/bedroom blur <0-40>` | How solid the panels over the room are, and how much they blur it |
| `/bedroom title console <text>`, `/bedroom title tape <text>` | Writes your own title on the console's screen or the tape's spine, up to 24 characters; with no text it goes back to the default |
| `/bedroom title pennant <text>`, `/bedroom title pennant-top <text>` | Writes your own team on the pennant's big line (up to 12 characters) or its small top line (up to 16), in capitals; with no text it goes back to the default |
| `/bedroom instant [on\|off]` | Shader switching (on) or sending the room again for every change (off) |
| `/bedroom stats` | Render counts and timings |
| `/bedroom calibrate` | Fits clicks to your window's shape |
| `/bedroom reset` | Every switch back to its default; titles and calibration stay |
| `/bedroom on`, `/bedroom off` | Sets or clears the theme |

The titles you set are kept in the plugin's store on your machine, under the `bedroom:saved` key.
The defaults, FAR MERIDIAN on the console, ROOFTOP on the tape and LANTERN HILL NIGHTJARS on the
pennant, are made up, as are the posters.

## Files

`hooks/register.tsx` is the module `hooks.json` loads; it registers each theme. The bedroom's own
files are in `hooks/bedroom/`: `register.tsx` its hooks, `scene/` draws the room, `lights.ts` is
the shader. `types/index.d.ts` declares what the settings card keeps in the session's state. `hooks/make-colors.js` and `hooks/make-colors.d.ts` are the color helper the built-in
`plugin-authoring` skill tells a theme mod to copy unchanged. The bedroom writes no files: its render
counts and timings are kept in memory for `/bedroom stats`.

## License

MIT (SPDX-License-Identifier: MIT).
