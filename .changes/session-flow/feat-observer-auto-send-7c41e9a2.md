---
bump: minor
---

### Added

- The observer can deliver its findings to the agent on its own: with `observer_auto_send` on, a finding raised mid-turn rides the agent's next model request, and one raised while idle starts a single observer turn. Two optional triggers join the live checks: `observer_change_check` checks after an editing step, and `observer_gate_check` holds outward commands such as `git push` until a check returns, refusing one on a finding and never blocking on an observer fault. Every number and text that shapes the observer's checks, notes, band, remembered findings and file retention is now an option, `observer_guidance` adds your own instructions to each check, and the check prompt names skill steps, standards, review criteria, plugin philosophy, code quality, and intent and vision. All new behavior is off by default.
