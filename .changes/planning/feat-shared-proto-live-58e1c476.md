---
bump: minor
---

### Added

- A shared interview can hold live prototypes, recorded but not yet started by any process. With "Live prototypes" on in the Host settings, Claude's `add-live` op records one (`L<N>`, pending) for a build folder under the data folder's `staging/` or a port on 127.0.0.1 other than the session's own, and a prototype variant links it with `live: {id, path}`. The owner approves or stops each entry from the prototype page (`POST /api/live/approve`, `POST /api/live/stop`), and a server on a port needs the owner's sample-data attestation. Until the owner approves an entry and it runs, no guest or leader receives its url. Stopping it, turning live prototypes off, or ending the session ends every entry it covers and keeps no url. The prototype page offers "Open live prototype" in a new tab with `rel="noopener noreferrer"` only while the entry runs, shows guests "Live version waiting for the host" while it is pending, and never frames a live prototype. A link path holding a fragment, `%23`, `//`, a scheme or a backslash is refused. This build starts no process, so Approve answers 503 `live-unavailable` and the entry stays pending. A session holding `lives` or a variant with a live link does not load in an earlier build.
