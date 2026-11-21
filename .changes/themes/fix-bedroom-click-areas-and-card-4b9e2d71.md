---
bump: patch
---

### Fixed

- A click on the console's right edge also started the tape, and a click where the lava lamp meets the wall light flipped both. The console, the tape's spine and the lava lamp now take clicks over slightly narrower areas, so every click flips one thing.
- While another plugin's theme covered the room, the settings card still said `theme: on` and its theme button cleared that theme instead of bringing the room back. The card now says `theme: covered` and its button puts the room back; `/bedroom on` does the same, and `/bedroom status` says which plugin's theme covers the room.
