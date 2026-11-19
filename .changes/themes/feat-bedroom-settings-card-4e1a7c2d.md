---
bump: minor
---

### Added

- A settings card for the bedroom theme: `/bedroom` alone, in the desktop app, shows a five-row card in the conversation with the theme on or off, reset and calibrate; a button for each switch showing its state; dim, glass and blur steps side by side; and the four title fields two to a row. Each button runs the same `/bedroom` command a person would type, and the card follows changes made by clicks in the room. A switch's button is inactive until the switch has finished changing; clicks in the room are never held back. Away from the desktop app, `/bedroom` still answers in text alone.
- `/bedroom status`: what is on and off, the answer `/bedroom` alone gives.

### Fixed

- Changing dim or a title no longer shows the lit room with the ceiling light off: while the room waits for the shader to come back, it shows as it stands, dusk included, and a click in that time is drawn into it. The console's title card no longer shows on the blue or tape screen of the room drawn without the shader.
- A switch turned from the card or a typed command moves once instead of twice, unless a click in the room has turned it the other way since.
