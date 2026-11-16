---
bump: major
---

### Removed

- The connected-page Artifact guard and its `connected_page_guard_enabled` option leave review for the guardrails plugin, which runs the same guard. Without guardrails enabled, nothing blocks publishing a connected page as an Artifact, which exposes the local session-bridge port. Enable guardrails to keep the guard, and set `connected_page_guard_enabled` again there if you had changed it: the value set here does not carry over. review now registers no hook.
- `scripts/check-hook-registration.sh` is removed with the hook it checked, and the node prerequisite's notice no longer names it.

### Added

- `/review:explain-change`'s `build-digest.mjs --connect` prints a warning on stderr, whether or not guardrails is enabled, that the page it wrote is local-only, works only on this machine and must never be published as an Artifact. Its stdout still prints only the page path.
