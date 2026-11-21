---
bump: minor
---

### Added

- On Windows, and under WSL through Windows, one player process mixes every bedroom sound for as long as sound is on, so a sound plays within about a tenth of a second of its click; it ends with sound off, the plugin unloading or the session ending. If it stops by itself after 20 seconds without a command, sound stays on and the next sound starts it again; only a failed start or a failing exit turns sound off, with the reason in `/bedroom sound`.
- The bed follows the picture: a change of weather cross-fades the beds over the time the window takes, from when the window starts to change; volume changes fade, and sound off fades out in 0.15 s.
- The room's things make quiet sounds: the desk lamp's and wall light's switches, the monitor's button and degauss, the console's fan and chime, the tape going in and out, and the cat's purr when clicked (`/bedroom sound objects on|off`).
- A sound bank: each kind has named entries and a default, chosen by `/bedroom sound pick <kind> <name>` or on the card's sounds button, and kept. A choice saved by 0.3 of the second cicadas recording loads as `river`; the other 0.3 choices play the default.
- The settings card's switch row ends with `pass`, `door` and `bolt`: someone passes the door, the hall light, and a lightning strike, each through its command; the card stays six rows. `door` is the hall light's switch and carries a check while the light is on, including when the hallway turns it on by itself; `pass` and `bolt` run once.
- A storm strikes about two times a minute at uneven gaps by default, each strike with its thunder; the `lightning` setting and `/bedroom weather lightning rare|normal|often` choose about one in three minutes (the shader's own schedule alone), two a minute or three.
- `/bedroom date MM-DD` holds the room on a day of the year for its sunrise and sunset; `spring`, `summer`, `autumn` and `winter` hold 04-20, 07-15, 10-15 and 01-15, and `auto` (the default, also the `date` setting) follows the real date. The clock's hours and the VCR keep the real time.

### Changed

- Sunrise and sunset follow the season by default (`sunrise` and `sunset` settings `auto`): worked out from the date for 40 degrees north and moved by the clock's daylight saving time, so a June sunset comes near 20:30 and a December one near 16:40; southern daylight saving time turns the season. An `HH:MM` setting holds that time all year, as before.
- Rain, the downpour and the storm are one recording of rain on a roof heard from indoors, the downpour and the storm heavier, so the three sound alike at the same distance. Thunder follows each strike after 1 to 6 seconds, quieter and rolling longer the farther the strike.
- By day the trees outside the window show clumps of leaves and leafy edges, and the far treeline more detail; at night more stars fill the sky. Dusk and evening look as before.
- Someone passing the door dims the hall light in the gap and on the floor softly as they go by, the dimming moving across the gap the way they walk and fading toward the top of the gap; it was a dark stripe. With the hall light on, its light also shows on the door's edge and under the door, and as Claude's context fills, a faint band rolls down the television's glass again.
- The settings card's four title fields show two to a row, wide enough for each title and its set button, in place of the time and the weather, so the card stays six rows.
- In dry weather the insects follow the hour all year: quiet at dawn and in the morning, a few distant cicadas at noon building to full by the golden hour and dusk, the cicadas giving way across the evening to crickets and katydids 6 dB quieter, and a little quieter again before dawn; each change eases with the picture. The night insects are a new bank kind, `crickets` (`katydids`, the default, or `crickets`), cut from CC0 recordings listed in `sounds/bedroom/sources.md`.
- `/bedroom sound pick` takes a kind, `cicadas`, `crickets`, `rain`, `thunder` or `tv`, and an entry's name or number; 0.3's `downpour` and `storm` kinds are gone, since the rain entry holds all three wet beds.
- The README states where `soundPlayer` is read from and how it runs.

### Fixed

- `/bedroom weather strike` in a storm is followed by thunder 1 to 4 seconds after the flash, as a scheduled strike is.
- `/bedroom hall pass` or `/bedroom hall light` asked again while the first is still showing now runs again once the first ends, where it reported success and did nothing, and its reply gives the time it really runs.
- `/bedroom tape|console on|off` to the state it is already in now says so and sends nothing while the shader runs, as the other switches do.
- `/bedroom weather strike`, `/bedroom hall pass` and `/bedroom hall light` asked in the shader's first 30 seconds after it starts, or while the room shows alone after a change, sent an event the shader drops and answered as if it would show; they now send nothing and say how many seconds to wait. A strike outside a storm names the weather it found.
- A lightning strike lights the sky in the window more brightly; at an evening storm the old flash was faint.
- Thunder could not be heard over the storm's rain: it plays at twice the volume's level, falling to the volume's own level for the farthest strike, and through the Windows mixer the bed dips to half while it rolls. A scheduled strike the shader does not draw (its first 30 seconds, or 30 seconds after a command hurries it) no longer brings thunder without a flash. `/bedroom sound` names the last one-shot sent and how long ago.
