---
bump: minor
---

### Added

- Time of day for the bedroom: the light follows the clock from sunrise to night (`/bedroom time auto`), or holds a phase (`/bedroom time noon`, `dusk`, `night` and the others, or a time as `HH:MM`). The VCR always shows the real time.
- Weather in the window: `auto` changes by itself every three hours and never picks a storm; `/bedroom weather clear`, `overcast`, `rain`, `downpour` or `storm` holds one.
- The television reacts to Claude: a faint flicker while a turn runs and a rolling band once the context is half full (`/bedroom signal on|off`).
- The hallway: now and then someone passes the door, or the hall light comes on (`/bedroom hall on|off`).
- `/bedroom shader off`, for diagnosis, shows the hand-drawn room alone for the rest of the session, now with the hour and the weather in its window; `/bedroom shader on` brings the shader back.
- Sound, off by default: the television's click as it turns on and off, cicadas from dusk through night when it is dry, and in wet weather rain, a heavier downpour or a storm with wind, with thunder after each flash (`/bedroom sound on|off|test`; `test` plays a silent file). Nothing plays until it is turned on; off, and a change of weather or hour, stop what is playing at once.
- The loops and the thunder are cut from public-domain and CC0 recordings, listed in `sounds/bedroom/SOURCES.md`, two of each to choose between with `/bedroom sound pick <kind> 1|2`.
- `/bedroom sound volume 0-100` sets the volume of every sound, kept with the other settings; the card steps it by ten.
- `/bedroom sync` redraws every switch from what is saved, and `/bedroom <setting> default` makes a setting follow the plugin's settings again.
- The settings card gains a row for the time of day, from the earliest light to night, a row for the weather, on/off buttons for the television's signal and the hallway, and sound with its volume.
- Plugin settings for the time of day, sunrise, sunset, weather, sound and its player, the signal, the hallway and the shader.

### Changed

- `/bedroom <switch> on|off` to the state the switch is already in now says so and sends nothing, where it briefly turned the switch back first.
- The settings card is six rows, seven while its titles button shows the four title fields on one row; the shader has no button on it.
- `/bedroom reset` also shows the room alone for seven seconds and puts the time, weather, signal, hallway, shader and sound choices back to the plugin's settings.
- Settings saved by 0.2 under `bedroom:saved` load unchanged.
