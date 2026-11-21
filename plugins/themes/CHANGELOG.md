# Changelog

All notable changes to the `themes` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.4.0] - 2026-11-21

### Added

- On Windows, and under WSL through Windows, one player process mixes every bedroom sound for as long as sound is on, so a sound plays within about a tenth of a second of its click; it fades out with sound off, the session's desktop window closing, the session ending, the process that started it going, or 9 seconds with no word from the mod (which sends one every 3 seconds), so the room is quiet within seconds of the app going away. One plays per session: after a reload the old one fades out before the new one starts. If it stops by itself or goes silent while sound is on, another starts; one that fails after playing is started again 10 seconds later; `/bedroom sound` says when sound is on but nothing plays, and why, with the mixer's process id.
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
- In dry weather the insects follow the hour all year: quiet at dawn, in the morning and at midday; the cicadas start faint four and a half hours before the room's sunset and build to full by the golden hour and dusk; across the evening they give way to crickets and katydids at half their level; at night the katydids fall quiet and the crickets carry on at 0.4, and at 0.3 before dawn. A held noon is quiet. Each change eases with the picture, the afternoon's build through the Windows mixer in one ease, and sound turned on partway through the evening starts both beds where the cross-fade is then. The night insects are a new bank kind, `night`: `auto` (the default) follows the hour, `katydids` or `crickets` holds one loop all night; both are cut from CC0 recordings listed in `sounds/bedroom/sources.md`.
- The cicadas' `auto` choice, the default, plays the `chorus` bed alone; `chorus` or `river` holds one recording, as before.
- `/bedroom sound pick` takes a kind, `cicadas`, `night`, `rain`, `thunder` or `tv`, and an entry's name or number; 0.3's `downpour` and `storm` kinds are gone, since the rain entry holds all three wet beds.
- The README states where `soundPlayer` is read from and how it runs.
- The made-up weather that changes by itself every three hours, never to a storm, is `random` (`/bedroom weather random` and the `weather` setting). `auto`, still the default, is to follow the real weather; with none connected it is random, and `/bedroom weather` says so. A saved `auto` loads as it was.

### Fixed

- `/bedroom weather strike` in a storm is followed by thunder 1 to 4 seconds after the flash, as a scheduled strike is.
- `/bedroom hall pass` or `/bedroom hall light` asked again while the first is still showing now runs again once the first ends, where it reported success and did nothing, and its reply gives the time it really runs.
- `/bedroom tape|console on|off` to the state it is already in now says so and sends nothing while the shader runs, as the other switches do.
- `/bedroom weather strike`, `/bedroom hall pass` and `/bedroom hall light` asked in the shader's first 30 seconds after it starts, or while the room shows alone after a change, sent an event the shader drops and answered as if it would show; they now send nothing and say how many seconds to wait. A strike outside a storm names the weather it found.
- A lightning strike lights the sky in the window more brightly; at an evening storm the old flash was faint.
- At night under overcast, rain, a downpour or a storm the window was black; the cloud now stays a dark blue-gray sky, a little lighter than the wall, with the moon a soft glow behind it, and the land still stands dark against it. The evening and before dawn under cloud are a little lighter too.
- Thunder could not be heard over the storm's rain: it plays at twice the volume's level, falling to the volume's own level for the farthest strike, and through the Windows mixer the bed dips to half while it rolls. A scheduled strike the shader does not draw (its first 30 seconds, or 30 seconds after a command hurries it) no longer brings thunder without a flash. `/bedroom sound` names the last one-shot sent and how long ago.
- The room's sound kept playing after the app was exited while its session ran on; it now fades out within seconds.
- After a reload, or a mixer that went away unseen, sound could stay silent while set on until it was turned off and on; the mod now notices and starts the mixer again.
- An evening set by command left the night insects near silence for over an hour, waiting on the clock's long cross-fade; a held evening now plays them at once, over the picture's quick ease.
- Another plugin clearing the theme, as theme-examples does after its fireworks, removed the bedroom until `/bedroom on`. While the room is on, the bedroom now puts its look back right after such a clear, the room showing alone for 7 seconds before the shader starts over it. A theme another plugin sets is left to show until it is cleared, and after `/bedroom off` the room stays off.

## [0.3.3] - 2026-11-21

### Changed

- `plugin.json` declares the mods floor as `engines["claude-code"]`, `">=2.1.287"`. Claude Code 2.1.323 and later read it and do not install, update or load the plugin outside that range; 2.1.76 through 2.1.322 ignore it, and 2.0.15 through 2.1.75 refuse to load a manifest that has it.

## [0.3.2] - 2026-11-21

### Fixed

- The bedroom sound test passes on a Windows host. Its stand-in for the file check now compares the probed path with the drive letter and backslashes removed, since the engine resolves `/usr/bin/ffplay` to a drive path such as `D:\usr\bin\ffplay` there ([#17823](https://github.com/melodic-software/claude-code-plugins/issues/17823)).

## [0.3.1] - 2026-11-20

### Changed

- The bedroom window builds its treeline and tree outlines once, when the scene loads, rather than on every draw.

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
