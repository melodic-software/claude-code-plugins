---
bump: minor
---

### Changed

- The monitoring lane replaces its rolling issues with status in each run's job summary and one incident issue per signal that needs action. `monitor.incidents` sets each signal's `open-hours` and `close-hours`: an incident opens only after the signal has stayed on past its open threshold and closes once clear past its close threshold, and a state change rewrites the body without a comment. Closing an incident as not planned or duplicate still mutes the signal. The lane closes the old rolling issues with a pointing comment and leaves their history in place.
