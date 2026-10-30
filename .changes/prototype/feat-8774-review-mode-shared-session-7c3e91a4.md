---
bump: minor
---

### Added

- `/prototype:explore-directions` has an opt-in review mode ([#8774](https://github.com/melodic-software/claude-code-plugins/issues/8774)): on the user's yes it starts `/planning:interview`'s shared session, asks one `prototype` question per screen with a companion four-outcome decision (approve as is, approve with tweaks, combine, rework), and reads the round's digest back as UI acceptance criteria and a record of the directions that lost. It publishes nothing to claude.ai, falls back to the local mockup when the shared session cannot start, and states its boundaries with the `/design` canvas, the playground and the bundled `prototype` skill. The discipline gains a scoped persistence exception for it.
