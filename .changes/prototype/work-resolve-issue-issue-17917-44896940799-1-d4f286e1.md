---
bump: patch
---

### Fixed

- Notes host: P, R, A, M and N now work while focus is inside the mockup. Before, the frame passed only Escape and T up to the host, so the shortcuts did nothing after a click into the mockup. A key the mockup handles and cancels with `preventDefault`, as the switcher does, stays in the mockup, so on a variant with motion R inside the mockup replays; keys typed in a field, or held with Ctrl, Alt or Meta, stay in the mockup ([#17917](https://github.com/melodic-software/claude-code-plugins/issues/17917)).
