---
bump: minor
---

### Added

- `/user-interface:audit`'s motion lane reviews an animation from its captured frame state: slow it down, record and scrub it, annotate the frame that feels wrong, and read a pasted export as data (its frame, recorded speed, per-element values and the timing between an input and a change). With nothing pasted it offers a capture through `/app-control:drive capture --kind animation` and runs it only after a yes. An ungated `:hover` rule is left to the `touch` lane, and the motion catalog now grades an ease-in on an exit that is not permanent as Important.
