# Changelog

All notable changes to the `themes` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

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
