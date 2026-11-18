---
bump: minor
---

### Added

- `/planning:design system` suggests three more threads in `design-threads.md`: `Quality scenarios`
  (each Brief quality requirement as a six-part scenario, never re-asked, deferred in one line on a
  prototype Brief), `Capacity estimates` (inputs, arithmetic and a `Basis:` line, an unknown input
  recorded as `target assumed ... revisit if ...`) and `Risks` (rows in the plan's
  `Risk | Likelihood | Impact | Mitigation` columns). The steps live in the new
  `skills/design/reference/system-scope.md`; the design gate is unchanged.
- `/planning:design-handoff` lists the `Risks` rows in its handoff summary and resume prompt, and
  `/planning:plan` starts its `### Risks and Mitigations` table from them.
- Eval cases `design-system-quality-scenarios`, `design-system-prototype-defers-scenarios` and
  `design-system-risk-list-plan-shape`.
