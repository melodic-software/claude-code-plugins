---
bump: minor
---

### Added

- Each interview round opens with a restate ([#9716](https://github.com/melodic-software/claude-code-plugins/issues/9716), gap G7): `add-round` with questions takes `restate` (`text` of at most 3 sentences, plus `decided` and `open` question id lists) and refuses a round without it, as R1 refuses a question without `commits`. It is stored per round in `rounds`, the page pins it as a card above the round's first question, and Activity gets a "Needs you" entry. A data dir without `rounds` still loads, renders and exports (`plugins/planning/surface/round.py`, `index.html`, `schema/`, `skills/interview/context/surface.md`).
