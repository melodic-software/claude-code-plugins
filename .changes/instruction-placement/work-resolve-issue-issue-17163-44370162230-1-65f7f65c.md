---
bump: minor
---

### Changed

- Rung 2 of the routing rubric no longer picks a mechanism from its own list. When `/corrections:codify` is available, `/instruction-placement:audit` and `/instruction-placement:realign` name the codify call for a mechanically checkable rule; otherwise they propose the strongest mechanism that can decide the rule and say the proposal is unproven. Both still report the route without building it and keep the prose in place, and realign still marks the finding `blocked` ([#17163](https://github.com/melodic-software/claude-code-plugins/issues/17163)).
