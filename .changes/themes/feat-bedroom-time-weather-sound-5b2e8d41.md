---
bump: minor
---

### Added

- Time of day for the bedroom: the light follows the clock from sunrise to night (`/bedroom time auto`), or holds a phase (`/bedroom time noon`, `dusk`, `night` and the others, or a time as `HH:MM`). The VCR always shows the real time.
- Weather in the window: `auto` changes by itself every three hours and never picks a storm; `/bedroom weather clear`, `overcast`, `rain`, `downpour` or `storm` holds one.
- The television reacts to Claude: a faint flicker while a turn runs and a rolling band once the context is half full (`/bedroom signal on|off`).
- The hallway: now and then someone passes the door, or the hall light comes on (`/bedroom hall on|off`).
- `/bedroom shader off` shows the hand-drawn room alone, now with the hour and the weather in its window; `/bedroom shader on` brings the shader back.
- Sound, off by default: the television's click, cicadas, rain and thunder (`/bedroom sound on|off|test`; `test` plays a silent file). Nothing plays until it is turned on.
- `/bedroom sync` redraws every switch from what is saved, and `/bedroom <setting> default` makes a setting follow the plugin's settings again.
- The settings card gains a row for the time of day, a row for the weather, and on/off buttons for the television's signal, the hallway, the shader and sound.
- Plugin settings for the time of day, sunrise, sunset, weather, sound and its player, the signal, the hallway and the shader.
- `/bedroom hall pass` and `/bedroom hall light` show a hallway pass or turn the hall light on (or off) now, and `/bedroom weather strike` brings one flash of lightning in a storm, each within about five seconds.
- The window shows the dusk view at every hour, lit for it: by day shaded trees, the far treeline, the field and the utility pole with its wires; at night a deep blue sky with stars and the moon, never a black window.
- Overcast covers the sky with cloud at every hour, and rain, a downpour and a storm differ in weight: how much falls, how fast and how long the streaks, the drops on the glass, the veil over the view and how dark the sky is; a storm also slants the rain in the wind.
- The hall light lights the whole gap beside the door, brightest at the top, and lays a wedge of light on the floor; a passer-by's shadow crosses the gap.

### Changed

- `/bedroom <switch> on|off` to the state the switch is already in now says so and sends nothing, where it briefly turned the switch back first.
- The settings card is seven rows, where it was five.
- `/bedroom instant off` is kept across sessions, as the `shader` choice.
- `/bedroom reset` also shows the room alone for seven seconds and puts the time, weather, signal, hallway, shader and sound choices back to the plugin's settings.
- Settings saved by 0.2 under `bedroom:saved` load unchanged.
- On an overcast or stormy day the room is lit less and flatter, and late at night the light low in the door's gap is fainter.
