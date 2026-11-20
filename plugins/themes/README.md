# themes

A home for backdrop themes for the Claude Code desktop app. Each theme lives in its own folder
under `hooks/`.

The first theme is bedroom: a teenager's bedroom in the country, about 2004, its light following
the time of day and the weather. More bedrooms, one per decade, are planned.

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
  `claude plugin test` pass on 2.1.329.

## Bedroom

A window with blinds onto the sky and the trees, a dresser with a television, VCR, game console and lava lamp, a
desk with a computer and lamp, posters, a pennant and a cat lying on the television. The room is
one SVG; a lighting shader over it runs at 30 frames a second and draws what each switch changes,
so a click changes the room without sending it again.

### What you can click

The television, the VCR (or the tape standing beside the console), the console, the
computer, the ceiling light switch by the door, the desk lamp and the lava lamp each switch on or
off. The cat purrs. If clicks land in the wrong place, run `/bedroom calibrate` and click the
bottom-left corner of the front of the dresser.

### Time of day, weather, the television and the hallway

- **Time of day.** By default the light follows your computer's clock: dusk from sunset, then
  evening, night, the gray before dawn, dawn, morning, midday and the golden hour. Sunrise and
  sunset are the plugin's `sunrise` and `sunset` settings (6:30 and 20:30 unless you change them).
  `/bedroom time noon` holds one phase all day; `/bedroom time auto` follows the clock again. The
  room starts at dusk and eases to the hour over about six seconds. The VCR always shows the real
  time.
- **Weather.** In the window only: overcast, rain, a downpour, or a storm with a soft flash in the
  sky about once in three minutes. `auto` changes by itself every three hours and never picks a
  storm; it asks no weather service, so every session gives the same weather at the same hour.
- **The television and Claude.** While a turn runs, the screen flickers faintly; once the context
  is half full, a pale band rolls down it now and then. `/bedroom signal off` stops both.
- **The hallway.** About once an hour someone passes the door, and now and then the hall light
  comes on for a few minutes. `/bedroom hall off` keeps the hallway still.
- **Without the shader.** `/bedroom shader off` shows the hand-drawn room alone, with the hour and
  the weather in its window; every change then sends the room again.
- **Sound.** Off by default, and nothing plays until you turn it on: `/bedroom sound on` plays the
  television's click, cicadas from dusk through the night when it is dry, rain, and thunder in a
  storm. `/bedroom sound test` plays a silent file and says whether the player ran. The sounds are
  made by code, not recorded. On macOS the app plays them; elsewhere the mod runs a player it finds
  on `PATH` (`powershell.exe` under WSL or Windows, `ffplay`, `paplay`, `aplay`), or the command in
  the `soundPlayer` setting, with `{file}` where the file goes.

Changing the time or the weather by command shows within a few seconds and eases over about six.

### The settings card

`/bedroom` alone shows a card in the conversation, so you need not know the words. It is seven rows,
so it fits without scrolling: the theme on or off, reset, calibrate and Close; a button for each
switch showing whether it is on; the time of day (auto and each phase, the chosen one checked); the
weather (auto and each kind); dim, glass and blur steps beside on/off buttons for the television's
signal, the hallway, the shader and sound; and the four title fields, two to a row (Enter sets one;
empty puts the default back). Each button runs the same `/bedroom`
command you would type, so it costs what that command costs: a switch changes in the shader without
the room being sent again. A switch's button draws dim, with `…` after its state, until the switch
has finished changing, about a second (three for the console, which boots), and a press on it
meanwhile does nothing; clicks in the room are never held back. The card follows changes made by
clicks in the room and by typed commands. Close puts it away; `/bedroom` shows it again at the end
of the conversation. Away from the desktop app, `/bedroom` answers in text alone.

### Dim and titles

Dim and the titles are drawn into the room itself, so changing one sends the room again. The room
then shows as it stands, ceiling light off included, for seven seconds while the app takes the new
room, and the shader takes it over again after that: the lights, screens and clock move again, and
clicks are answered at once. A click in those seven seconds still counts and is drawn into the room.

### The `/bedroom` command

| Command | Does |
|---|---|
| `/bedroom` | Says what is on and off; in the desktop app, also shows the settings card |
| `/bedroom status` | Says what is on and off |
| `/bedroom <tv\|tape\|console\|pc\|light\|lamp\|lava> [on\|off]` | Switches one thing; with neither word it flips. A switch already in that state stays as it is |
| `/bedroom time <auto\|dusk\|evening\|night\|predawn\|dawn\|morning\|noon\|golden\|HH:MM>` | Follows the clock, or holds a phase (`HH:MM` holds the phase of that hour); alone, says which |
| `/bedroom weather <auto\|clear\|overcast\|rain\|downpour\|storm>` | The weather in the window; alone, says which |
| `/bedroom signal [on\|off]` | The television reacting to Claude |
| `/bedroom hall <on\|off>` | The hallway's passes and hall light |
| `/bedroom shader [on\|off]` | The shader (on), or the hand-drawn room alone (off) |
| `/bedroom sound <on\|off\|test>` | Sound, off by default; `test` plays a silent file |
| `/bedroom <time\|weather\|signal\|hall\|shader\|sound> default` | Follows the plugin's setting again |
| `/bedroom sync` | Shows the room alone for seven seconds, then brings the shader back with every switch as saved |
| `/bedroom dim <0-80>` | Lays a dark veil over the room |
| `/bedroom glass <0-95>`, `/bedroom blur <0-40>` | How solid the panels over the room are, and how much they blur it |
| `/bedroom title console <text>`, `/bedroom title tape <text>` | Writes your own title on the console's screen or the tape's spine, up to 24 characters; with no text it goes back to the default |
| `/bedroom title pennant <text>`, `/bedroom title pennant-top <text>` | Writes your own team on the pennant's big line (up to 12 characters) or its small top line (up to 16), in capitals; with no text it goes back to the default |
| `/bedroom instant [on\|off]` | Another word for `/bedroom shader` |
| `/bedroom stats` | Render counts and timings |
| `/bedroom calibrate` | Fits clicks to your window's shape |
| `/bedroom reset` | Every switch, dim, glass and blur back to its default, and time, weather, signal, hallway, shader and sound back to the plugin's settings; titles and calibration stay |
| `/bedroom on`, `/bedroom off` | Sets or clears the theme |

The titles you set, and the choices the commands above hold, are kept in the plugin's store on your
machine, under the `bedroom:saved` key; settings saved by version 0.2 load as they were.
The defaults, FAR MERIDIAN on the console, ROOFTOP on the tape and LANTERN HILL NIGHTJARS on the
pennant, are made up, as are the posters.

## Files

`hooks/register.tsx` is the module `hooks.json` loads; it registers each theme. The bedroom's own
files are in `hooks/bedroom/`: `register.tsx` its hooks, `card.tsx` the settings card, `core/` the
switches, commands, saved settings and what is sent to the shader, `pieces/` the time of day,
weather, television, hallway, room without the shader and sound, `scene/` draws the room, and
`lights.ts` is the shader. `lights.ts`, `core/signals.gen.ts` and `pieces/index.ts` are generated
together from a GLSL source by a build script kept outside this repository. `sounds/bedroom/` holds
the sound files. `types/index.d.ts` declares what the settings card and the minute clock keep in the
session's state. `hooks/make-colors.js` and `hooks/make-colors.d.ts` are the color helper the
built-in `plugin-authoring` skill tells a theme mod to copy unchanged. The bedroom writes no files:
its render counts and timings are kept in memory for `/bedroom stats`, and its notes go to the debug
log.

## License

MIT (SPDX-License-Identifier: MIT).
