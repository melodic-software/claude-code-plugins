---
bump: patch
---

### Fixed

- A broker `kill-switch` refusal at the read file's broker-check (a switch turned on after the run read its variables) now ends that job green as a stop instead of failing it: `request-lane-token` takes `kill-switch-ok` in `check` mode, and broker-check passes it and reads its allow from the new `allowed` output. The run job and every job after it skip, no lease is claimed, no lane run report comment is posted, and the check is neutral `kill-switch`. The read file exposes the stop as `skip-reason`, and work-unblock still re-fires an issue whose broker-check stopped this way. Every other denial still fails red.
