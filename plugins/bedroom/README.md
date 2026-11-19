# bedroom

A mod for the Claude Code desktop app. It sets a dark theme whose backdrop is a teenager's bedroom
in the country at dusk, about 2004: a window with blinds onto the sky, a dresser with a television,
VCR, game console and lava lamp, a desk with a computer and lamp, posters, a pennant and a cat
lying on the television. The room is one SVG; a lighting shader over it runs at 30 frames a second and draws
what each switch changes, so a click changes the room without sending it again.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install bedroom@melodic-software
/plugin enable bedroom
```

The catalog entry sets `defaultEnabled: false`, because the backdrop takes over the whole window;
`/plugin enable bedroom` turns it on. `/bedroom off` clears the theme for the session.

## Requirements

- The Claude Code desktop app. The mod draws only on the desktop surface; a terminal session loads
  it and draws nothing.
- Claude Code 2.1.287 or later, the floor for mods. `claude plugin validate` and
  `claude plugin test` pass on 2.1.328.

## What you can click

The television, the VCR (or the tape standing beside the console), the console, the
computer, the ceiling light switch by the door, the desk lamp and the lava lamp each switch on or
off. The cat purrs. If clicks land in the wrong place, run `/bedroom calibrate` and click the
bottom-left corner of the front of the dresser.

## The `/bedroom` command

| Command | Does |
|---|---|
| `/bedroom` | Says what is on and off |
| `/bedroom <tv\|tape\|console\|pc\|light\|lamp\|lava> [on\|off]` | Switches one thing; with neither word it flips |
| `/bedroom dim <0-80>` | Lays a dark veil over the room |
| `/bedroom glass <0-95>`, `/bedroom blur <0-40>` | How solid the panels over the room are, and how much they blur it |
| `/bedroom title console <text>`, `/bedroom title tape <text>` | Writes your own title on the console's screen or the tape's spine, up to 24 characters; with no text it goes back to the default |
| `/bedroom instant [on\|off]` | Shader switching (on) or sending the room again for every change (off) |
| `/bedroom stats` | Render counts and timings |
| `/bedroom calibrate` | Fits clicks to your window's shape |
| `/bedroom reset` | Every switch back to its default; titles and calibration stay |
| `/bedroom on`, `/bedroom off` | Sets or clears the theme |

The titles you set are kept in the mod's store on your machine. The defaults, FAR MERIDIAN on the
console and ROOFTOP on the tape, are made up, as are the pennant's team and the posters.

## Files

`hooks/register.tsx` is the module; `hooks/scene/` draws the room; `hooks/lights.ts` is the
shader. `hooks/make-colors.js` and `hooks/make-colors.d.ts` are the color helper the built-in
`plugin-authoring` skill tells a theme mod to copy unchanged. The mod writes `telemetry.json`
(render counts and recent events) in its own plugin folder and nowhere else.

## License

MIT (SPDX-License-Identifier: MIT).
