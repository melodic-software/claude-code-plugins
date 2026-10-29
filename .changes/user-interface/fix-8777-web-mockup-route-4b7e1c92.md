---
bump: patch
---

### Fixed

- `/user-interface:design`: web mockups now have one route. The Claude Design gotcha no longer sends every mockup to the `Artifact` tool: it covers the design-system route, and mockups follow the `mockups-variants` rows, `/prototype:explore-directions` first and the `Artifact` tool only when no higher row passes routing, for example when that skill is not installed. The handoff to `/prototype:explore-directions` passes on the tokens, components and screens Step 2 found, so detection runs once.
