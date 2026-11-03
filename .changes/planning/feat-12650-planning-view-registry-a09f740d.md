---
bump: minor
---

### Added

- `/planning:design` offers a design view of PLAN.md's `## Design` section after the handoff gate passes, built by `scripts/build-view.mjs design --record <PLAN.md>` from a checked-in template (#12650).
- `scripts/build-view.mjs --option <medium option>` resolves the medium through the shared resolver, runs the publish gate over a publishing medium, builds the page and hands it to the medium's registry entry, then prints the delivery and the `view: <medium> (<what decided it>)` report line. A new medium needs no edit to the planning skills.

### Changed

- The plan, brainstorm and design views ship a private Artifact as their default medium. The publish gate keeps the view a local file for a repository that is not public or a record with anything credential-shaped in it, unless the `medium` option or the request says to publish; set the `medium` option to `file` to keep them local. The PRD and interview views stay local files.
- The plan and brainstorm views render as entries of the shared view-kind registry; their JSON shapes are unchanged.
