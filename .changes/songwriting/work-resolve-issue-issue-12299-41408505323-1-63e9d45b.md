---
bump: patch
---

### Changed

- The `eight-plus-candidates` grader in `rh-window-menu-no-winner` and `rh-release-identity-menu` is now LLM-judged and counts candidates however a reply lays them out. The regex it replaces counted list lines and table rows, so it failed a tier table with several candidates per row and a list line with several candidates. Its samples add those layouts and inline candidates, and a one-line inline list of eight now passes.
