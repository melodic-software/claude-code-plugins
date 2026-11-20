---
bump: minor
---

### Added

- Time of day for the bedroom: the light follows the clock from sunrise to night (`/bedroom time auto`), or holds a phase (`/bedroom time noon`, `dusk`, `night` and the others, or a time as `HH:MM`). The VCR always shows the real time.
- Weather in the window: `auto` changes by itself every three hours and never picks a storm; `/bedroom weather clear`, `overcast`, `rain`, `downpour` or `storm` holds one.
- The television reacts to Claude: a faint flicker while a turn runs and a rolling band once the context is half full (`/bedroom signal on|off`).
- The hallway: now and then someone passes the door, or the hall light comes on (`/bedroom hall on|off`).
- `/bedroom shader off`, for diagnosis, shows the hand-drawn room alone for the rest of the session, now with the hour and the weather in its window; `/bedroom shader on` brings the shader back.
- Sound, off by default (`/bedroom sound on|off|test`): cicadas from dusk through night when it is dry; in wet weather rain on the roof, the same rain heavier as a downpour, or a storm with wind; the television's click as it turns on and off; and thunder 1 to 6 s after each lightning strike, quieter and rolling longer the farther the strike. Nothing plays until it is turned on.
- The bed fades with the picture: a change of weather cross-fades the beds over the time the window takes, from when the window starts to change; volume changes fade, and sound off fades out in 0.15 s.
- On Windows, and under WSL through Windows, one player process mixes every sound for as long as sound is on, so a sound plays within about a tenth of a second of its click; it ends with sound off, the plugin unloading or the session ending.
- The room's things make quiet sounds: the desk lamp's and wall light's switches, the monitor's button and degauss, the console's fan and chime, the tape going in and out, and the cat's purr when clicked (`/bedroom sound objects on|off`).
- A sound bank: each kind has named entries and a default, chosen by `/bedroom sound pick <kind> <name>` or on the card and kept. The recordings are public-domain and CC0, listed in `sounds/bedroom/SOURCES.md`.
- `/bedroom sound volume 0-100` sets the volume of every sound, kept with the other settings; the card steps it by ten.
- `/bedroom sync` redraws every switch from what is saved, and `/bedroom <setting> default` makes a setting follow the plugin's settings again.
- The settings card gains a row for the time of day, from the earliest light to night, a row for the weather, on/off buttons for the television's signal and the hallway, and sound with its volume, the bed playing and the sound bank.
- Plugin settings for the time of day, sunrise, sunset, weather, sound and its player, the signal, the hallway and the shader.

### Changed

- `/bedroom <switch> on|off` to the state the switch is already in now says so and sends nothing, where it briefly turned the switch back first.
- The settings card is six rows whatever is open: the four title fields show two to a row, wide enough for each title and its set button, in place of the time and the weather, and so does the sound bank; the shader has no button on it.
- `/bedroom reset` also shows the room alone for seven seconds and puts the time, weather, signal, hallway, shader and sound choices back to the plugin's settings.
- Settings saved by 0.2 under `bedroom:saved` load unchanged.
