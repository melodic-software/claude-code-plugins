---
bump: minor
---

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
