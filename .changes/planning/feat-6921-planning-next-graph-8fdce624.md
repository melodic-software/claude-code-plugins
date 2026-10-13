---
bump: minor
---

### Changed

- **The planning chain's `## Next` sections follow `/session-flow:workflow`'s ladder ([#6921](https://github.com/melodic-software/claude-code-plugins/issues/6921)).** `/planning:questionnaire`, `/planning:audit-answers` and `/planning:devils-advocate` gain a `## Next`. `/planning:prd` and `/planning:interview` now route a locked Brief or PRD, and `/planning:wayfind` a map closed on a PLAN, to `/planning:design` (which records a one-line early exit when no design question is open) instead of straight to `/planning:plan`; a small task whose acceptance criteria are the plan still goes straight to implementation, and an unsure or mid-flow arrival still routes to `/session-flow:workflow`. `/planning:questionnaire` gets inbound routes from the interview and the PRD. `/planning:plan` sends a plan that a later session, an AFK lane or another person picks up to `/work-items:decompose`, matching the ladder's decompose trigger. A locked Brief or PRD that is one unit of work routes to `/work-items:track add --agent-ready` as a single tracker item. `scripts/check-next-graph.py` keeps the graph that way.
