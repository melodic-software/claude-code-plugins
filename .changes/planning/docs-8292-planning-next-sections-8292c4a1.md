---
bump: patch
---

### Changed

- `/planning:draft-goal-condition` gains a `## Next` section: `/implementation:implement` when an approved plan runs in this session under the armed goal, `/session-flow:continue-in-background` when the run goes on while the person is away, `/work-items:decompose` when the lever routed to multi-window work, and `/planning:interview` when the intent was too vague to draft.
- The planning skills' `## Next` sections name only the next step. `/planning:questionnaire` leaves `/planning:interview`'s and `/planning:prd`'s `## Next`, since it runs beside the next step; prd's hand-off now says so, in the interview's words. `/naming:name-it-better` and `/architecture:record-decision` leave `/planning:design`'s `## Next` for its relationship table, marked **During.** `/architecture:record-decision` also leaves `/planning:design-handoff`'s `## Next`: its hand-off already offers the ADR and now says the offer runs beside the next step.
- Each `## Next` bullet names one skill: `/planning:prd`'s splits its combined bullet, `/planning:wayfind`'s gives each map destination its own bullet and drops the general `/session-flow:workflow` fallback to stay within four, and `/planning:setup`'s line drops its backticks to match its siblings. `/planning:brainstorm` routes to `/planning:design` only once the contract is locked, in line with `/session-flow:workflow`'s stage order.
