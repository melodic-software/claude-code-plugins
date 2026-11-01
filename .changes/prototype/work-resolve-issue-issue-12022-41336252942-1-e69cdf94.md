---
bump: minor
---

### Added

- `/prototype:pressure-test observe` runs the variants of a fork a run can settle without a person at the keys: the agent builds each variant, drives them all from one harness on the same inputs, records behavior, output and timing per variant (timing labeled unqualified), and ends with a recommendation naming the variant and the evidence. Product and preference calls stay with the person, a fork that is itself a performance target goes to `/performance:goal`, and the auto-invoke gate, durable-note capture and shell deletion are unchanged. A new eval case, `pt-observe-recommends`, covers it ([#12022](https://github.com/melodic-software/claude-code-plugins/issues/12022)).
