---
bump: patch
---

### Added

- A `visualize` eval case: a dashboard request whose natural implementation loads an external charting library and a remote logo must still produce an Artifact page that inlines its CSS, JS and images and makes no network call, even to a host the Artifact CSP allows.
