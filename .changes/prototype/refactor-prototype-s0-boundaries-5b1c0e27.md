---
bump: patch
---

### Changed

- `/prototype:explore-directions` carries one `## Boundary` section for the `design`, `ClaudeDesign`
  and `playground` surfaces, keeping the suggest sentence, routing split and mutation gate; the
  full rules move to `reference/boundaries.md`. No behavior change.

### Added

- Eval case `ed-claude-design-project-routes`: a request naming an existing claude.ai/design
  project is routed to that project through the `ClaudeDesign` tool, or to throwaway variants with
  the reason when the tool is not available, and nothing is written to the project before the plan
  is approved.
- Eval case `ed-design-offer-shadowed`: with a local skill named `design` in the listing, no
  `/design` canvas offer is made and the user is told why.
