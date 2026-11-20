# Changelog

All notable changes to the `themes` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.3.0] - 2026-11-20

### Added

- Time of day for the bedroom: the light follows the clock from sunrise to night (`/bedroom time auto`), or holds a phase (`/bedroom time noon`, `dusk`, `night` and the others, or a time as `HH:MM`). The VCR always shows the real time.
- Weather in the window: `auto` changes by itself every three hours and never picks a storm; `/bedroom weather clear`, `overcast`, `rain`, `downpour` or `storm` holds one.
- The television reacts to Claude: a faint flicker while a turn runs (`/bedroom signal on|off`).
- The hallway: now and then someone passes the door, or the hall light comes on (`/bedroom hall on|off`).
- `/bedroom shader off`, for diagnosis, shows the hand-drawn room alone for the rest of the session, now with the hour and the weather in its window; `/bedroom shader on` brings the shader back.
- Sound, off by default: the television's click as it turns on and off, cicadas from dusk through night when it is dry, and in wet weather rain, a heavier downpour or a storm with wind, with thunder after each flash (`/bedroom sound on|off|test`; `test` plays a silent file). Nothing plays until it is turned on; off, and a change of weather or hour, stop what is playing at once.
- The loops and the thunder are cut from public-domain and CC0 recordings, listed in `sounds/bedroom/sources.md`, two of each to choose between with `/bedroom sound pick <kind> 1|2`.
- `/bedroom sound volume 0-100` sets the volume of every sound, kept with the other settings; the card steps it by ten.
- `/bedroom sync` redraws every switch from what is saved, and `/bedroom <setting> default` makes a setting follow the plugin's settings again.
- The settings card gains a row for the time of day, from the earliest light to night, a row for the weather, on/off buttons for the television's signal and the hallway, and sound with its volume.
- Plugin settings for the time of day, sunrise, sunset, weather, sound and its player, the signal, the hallway and the shader.
- `/bedroom hall pass` and `/bedroom hall light` show a hallway pass or turn the hall light on (or off) now, and `/bedroom weather strike` brings one flash of lightning in a storm, each within about five seconds.
- The window shows the dusk view at every hour, lit for it: by day shaded trees, the far treeline, the field and the utility pole with its wires; at night a deep blue sky with stars and the moon, never a black window.
- Overcast covers the sky with cloud at every hour, and rain, a downpour and a storm differ in weight: how much falls, how fast and how long the streaks, the drops on the glass, the veil over the view and how dark the sky is; a storm also slants the rain in the wind.
- The wall switch by the door shows the ceiling light: its toggle stands up when the light is on and snaps down when it goes off.
- The hall light lights the whole gap beside the door, brightest at the top, and lays a wedge of light on the floor; a passer-by's shadow crosses the gap.

### Changed

- `/bedroom <switch> on|off` to the state the switch is already in now says so and sends nothing, where it briefly turned the switch back first.
- The settings card is six rows, seven while its titles button shows the four title fields on one row; the shader has no button on it.
- `/bedroom reset` also shows the room alone for seven seconds and puts the time, weather, signal, hallway, shader and sound choices back to the plugin's settings.
- Settings saved by 0.2 under `bedroom:saved` load unchanged.
- On an overcast or stormy day the room is lit less and flatter, and late at night the light low in the door's gap is fainter.
- At dusk the desk, the chair, the dresser, the stand under the television and the door read in the shadows, the desk lamp lights more of the desk, and the lava lamp's glow on the wall is wider.

## [0.2.1] - 2026-11-20

### Fixed

- Clicks on the bedroom room work again in the desktop app. Dim is drawn into the room once more instead of a veil laid over it, which caught every click; a dim step shows the room drawn without the shader until it settles, then the shader takes the room back at the new dim.

## [0.2.0] - 2026-11-20

### Added

- A settings card for the bedroom theme: `/bedroom` alone, in the desktop app, shows a five-row card in the conversation with the theme on or off, reset and calibrate; a button for each switch showing its state; dim, glass and blur steps side by side; and the four title fields two to a row. Each button runs the same `/bedroom` command a person would type, and the card follows changes made by clicks in the room. A switch's button is inactive until the switch has finished changing; clicks in the room are never held back. Away from the desktop app, `/bedroom` still answers in text alone.
- `/bedroom status`: what is on and off, the answer `/bedroom` alone gives.

### Fixed

- A dim step darkens a veil over the room and no longer sends the room again, so the shader keeps running through it. Changing a title no longer shows the lit room with the ceiling light off while the room waits for the shader to come back: it shows as it stands, dusk included, and a click in that time is drawn into it. The console's title card no longer shows on the blue or tape screen of the room drawn without the shader.
- A switch turned from the card or a typed command moves once instead of twice, unless a click in the room has turned it the other way since.

## [0.1.0] - 2026-11-19

### Added

- The `themes` plugin, off by default: a home for backdrop themes for the Claude Code desktop app. Its first theme, bedroom, sets a dark theme whose backdrop is a teenager's bedroom at dusk, drawn as one SVG with a lighting shader at 30 frames a second. A click on the television, VCR, console, computer, ceiling light, desk lamp or lava lamp switches it, answered by the shader without sending the room again.
- The `/bedroom` command: each switch on or off, `dim`, `glass`, `blur`, `title console <text>`, `title tape <text>`, `title pennant <text>` and `title pennant-top <text>` for your own titles (kept on your machine; the defaults are made up), `instant`, `stats`, `calibrate`, `reset`, `on` and `off`.
