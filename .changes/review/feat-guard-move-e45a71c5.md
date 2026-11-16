---
bump: major
---

### Removed

- The connected-page Artifact guard and its `connected_page_guard_enabled` option leave review for the guardrails plugin, which runs the same guard. Enable guardrails to keep it, and set `connected_page_guard_enabled` again there if you had changed it: the value set here does not carry over. review now registers no hook.
- `scripts/check-hook-registration.sh` is removed with the hook it checked, and the node prerequisite's notice no longer names it.
