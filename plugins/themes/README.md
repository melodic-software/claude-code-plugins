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
  time. The view outside is the dusk view at every hour, lit for it: by day the trees, the far
  treeline, the field and the utility pole with its wires in daylight; at night a deep blue sky
  with stars and the moon over the dark trees and the yard light.
- **Weather.** In the window only. Overcast covers the sky with cloud at every hour. Rain falls
  light and slow with a few drops on the glass; a downpour adds a heavier, faster fall, more drops
  and a thicker veil; a storm slants the rain in the wind, darkens the sky further and flashes
  softly in it about once in three minutes. `auto` changes by itself every three hours and never
  picks a storm; it asks no weather service, so every session gives the same weather at the same
  hour. In a storm, `/bedroom weather strike` brings a flash within about five seconds.
- **The television and Claude.** While a turn runs, the screen flickers faintly.
  `/bedroom signal off` stops it.
- **The hallway.** The gap beside the door looks into a hall with a ceiling light. With it off, a
  faint light spills low in the gap, fainter late at night. About once an hour someone passes the
  door, and their shadow crosses the gap; now and then the hall light comes on for three minutes,
  lighting the whole gap, brightest at the top, and laying a wedge of light on the floor.
  `/bedroom hall pass` and `/bedroom hall light` show one now (the light turns off again if it is
  on); `/bedroom hall off` keeps the hallway still.
- **Sound.** Off by default, and nothing plays until you turn it on: `/bedroom sound on` plays the
  television's click as it turns on and off, cicadas from dusk through the night when it is dry,
  and in wet weather no cicadas but rain, a heavier downpour, or a storm (the downpour with wind),
  with thunder after each flash. One loop plays at a time, and it changes as soon as the weather or
  the hour does. `/bedroom sound off` stops what is playing at once.
  - `/bedroom sound volume 0-100` sets the volume for every sound (70 unless you change it; 0
    plays nothing); the card steps it by ten.
  - Each loop and the thunder come from public-domain or CC0 recordings, two of each to choose
    between by ear: `/bedroom sound pick cicadas 2` (or `rain`, `downpour`, `storm`, `thunder`;
    `1` is the default). `sounds/bedroom/sources.md` lists each recording, its page and its
    license. The television's sounds are made by code.
  - On macOS the app plays the sounds. Elsewhere the mod runs a player it finds on `PATH`:
    `powershell.exe` under WSL or Windows, `ffplay`, `paplay` or `aplay`. Or it runs the command in
    the `soundPlayer` setting, with `{file}` where the file goes and `{volume}` for 0 to 100. The
    Windows player and `ffplay` repeat a loop themselves and stop within a fifth of a second.
    `paplay`, `aplay` and a `soundPlayer` command play a loop as a chain of plays. `aplay` has no
    volume of its own.
  - `/bedroom sound test` plays a silent file and says whether the player ran. `/bedroom sound`
    alone says the volume, the recordings chosen and the player.

Changing the time or the weather by command shows within a few seconds and eases over about six.

### The settings card

`/bedroom` alone shows a card in the conversation, so you need not know the words. It is six rows,
seven with the titles shown, so it fits without scrolling: the theme on or off, reset, calibrate,
titles and Close; a button for each switch showing whether it is on; the time of day (auto, then
each phase from the gray before dawn to night, the chosen one checked); the weather (auto and each
kind); dim, glass and blur steps beside on/off buttons for the television's signal and the
hallway; sound on or off with its volume, and the last press's answer; and, while titles is on,
the four title fields on one row (Enter sets one; empty puts the default back). Each button runs the same `/bedroom`
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
| `/bedroom weather strike` | In a storm, one flash of lightning within about five seconds; at most one each 20 seconds |
| `/bedroom signal [on\|off]` | The television reacting to Claude |
| `/bedroom hall <on\|off>` | The hallway's passes and hall light |
| `/bedroom hall <pass\|light>` | While the hallway is on: someone passes the door, or the hall light turns on for three minutes (off, if it is on), within about five seconds |
| `/bedroom sound <on\|off\|test>` | Sound, off by default; `test` plays a silent file |
| `/bedroom sound volume <0-100>` | The volume of every sound |
| `/bedroom sound pick <cicadas\|rain\|downpour\|storm\|thunder> <1\|2>` | Which of two recordings a kind plays |
| `/bedroom <time\|weather\|signal\|hall\|sound> default` | Follows the plugin's setting again |
| `/bedroom sync` | Shows the room alone for seven seconds, then brings the shader back with every switch as saved |
| `/bedroom dim <0-80>` | Lays a dark veil over the room |
| `/bedroom glass <0-95>`, `/bedroom blur <0-40>` | How solid the panels over the room are, and how much they blur it |
| `/bedroom title console <text>`, `/bedroom title tape <text>` | Writes your own title on the console's screen or the tape's spine, up to 24 characters; with no text it goes back to the default |
| `/bedroom title pennant <text>`, `/bedroom title pennant-top <text>` | Writes your own team on the pennant's big line (up to 12 characters) or its small top line (up to 16), in capitals; with no text it goes back to the default |
| `/bedroom stats` | Render counts and timings |
| `/bedroom calibrate` | Fits clicks to your window's shape |
| `/bedroom reset` | Every switch, dim, glass and blur back to its default, and time, weather, signal, hallway and sound back to the plugin's settings; titles, calibration, volume and recordings stay |
| `/bedroom on`, `/bedroom off` | Sets or clears the theme |

For diagnosis, `/bedroom shader off` (or `instant off`) shows the hand-drawn room alone for the rest
of the session, with no fades, clock or lamp light, sending it again on every change; `/bedroom
shader on` brings the shader back, and a new session always starts with it. The same hand-drawn
room shows by itself when the app stops the shader, and for seven seconds after the room is sent.

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

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. For how Claude Code asks for
these and hands them to the plugin, see [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration).

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `time` | string | `"auto"` | auto follows the clock; a phase holds that light all day. |
| `sunrise` | string | `"06:30"` | Local time of sunrise, HH:MM from 04:00 to 09:00. |
| `sunset` | string | `"20:30"` | Local time of sunset, HH:MM from 16:00 to 22:00. |
| `weather` | string | `"auto"` | auto changes by itself every three hours and never picks a storm. |
| `sound` | boolean | `false` | The television's click, cicadas, rain, a downpour, a storm and thunder. Off by default. |
| `soundPlayer` | string | *(none)* | Empty: found at run time. Else a command line with {file} where the sound file goes and {volume} for 0 to 100. |
| `signal` | boolean | `true` | The screen flickers while Claude works. |
| `hall` | boolean | `true` | Now and then someone passes the door, or the hall light comes on. |
| `shader` | boolean | `true` | For diagnosis. Off: the hand-drawn room alone, with no fades, clock or lamp light, sent again on every change. |

### How to set these

Set the options above for `themes@<marketplace>`, replacing `<marketplace>` with the
marketplace you installed this plugin from:

- **In a session or headless:** [`/plugin` in a session](https://code.claude.com/docs/en/plugins/cli-reference#plugin-in-a-session) or
  [`claude plugin configure`](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure). The configure command is the preferred
  headless route in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/plugin-reconfiguration/README.md), which records its limits.
- **By hand:** under [`pluginConfigs`](https://code.claude.com/docs/en/settings-reference#pluginconfigs) in your **user** settings.

Do **not** uninstall the plugin to reconfigure it: see [What an uninstall deletes and keeps](https://code.claude.com/docs/en/plugins/cli-reference#what-an-uninstall-deletes-and-keeps).
For a Claude Code release without `plugin configure`, see [Plugin install](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install).

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration)
- [Plugin configure](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure)
- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install)
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills)
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect)
- [Manage installed plugins](https://code.claude.com/docs/en/plugins/install#manage-installed-plugins)

<!-- END GENERATED: plugin options -->

## License

MIT (SPDX-License-Identifier: MIT).
