---
bump: minor
---

### Added

- keep-going prints one environment snapshot block after inspecting real state and before any recovery action: account, 5-hour and 7-day windows, context zone, each off-thread item with its liveness verdict, the gap, and the stop's cause as evidence. A field with no reading says unknown and why.

### Changed

- keep-going's boundary now says the cause line is shown and never used to choose a recovery method.
