---
bump: minor
---

### Added

- On Windows, and under WSL through Windows, one player process mixes every bedroom sound for as long as sound is on, so a sound plays within about a tenth of a second of its click; it ends with sound off, the plugin unloading or the session ending.
- The bed follows the picture: a change of weather cross-fades the beds over the time the window takes, from when the window starts to change; volume changes fade, and sound off fades out in 0.15 s.
- The room's things make quiet sounds: the desk lamp's and wall light's switches, the monitor's button and degauss, the console's fan and chime, the tape going in and out, and the cat's purr when clicked (`/bedroom sound objects on|off`).
- A sound bank: each kind has named entries and a default, chosen by `/bedroom sound pick <kind> <name>` or on the card's sounds button, and kept. A choice saved by 0.3 of the second cicadas recording loads as `river`; the other 0.3 choices play the default.

### Changed

- Rain, the downpour and the storm are one recording of rain on a roof heard from indoors, the downpour and the storm heavier, so the three sound alike at the same distance. Thunder follows each strike after 1 to 6 seconds, quieter and rolling longer the farther the strike.
- The settings card's four title fields show two to a row, wide enough for each title and its set button, in place of the time and the weather, so the card stays six rows.
- `/bedroom sound pick` takes a kind, `cicadas`, `rain`, `thunder` or `tv`, and an entry's name or number; 0.3's `downpour` and `storm` kinds are gone, since the rain entry holds all three wet beds.
- The README states where `soundPlayer` is read from and how it runs.

### Fixed

- `/bedroom weather strike` in a storm is followed by thunder 1 to 4 seconds after the flash, as a scheduled strike is.
- `/bedroom hall pass` or `/bedroom hall light` asked again while the first is still showing now runs again once the first ends, where it reported success and did nothing.
- `/bedroom tape|console on|off` to the state it is already in now says so and sends nothing while the shader runs, as the other switches do.
