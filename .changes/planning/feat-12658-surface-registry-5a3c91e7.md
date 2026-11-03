---
bump: minor
---

### Added

- `interview`: a surface registry, `surfaces/registry.mjs`, with one entry file per surface under `surfaces/entries/` (terminal, page, shared session). `resolve` picks the surface from a surface the user asks for in the session, then the plugin's `surface` option, then a `surface` key in the repository's `.claude/interview-surface.json`, then the plugin default; a rendered-view medium setting never moves it. Adding a surface or a shared-session variant is adding an entry file, with no edit to the skill (#12658).
- `interview`: with `surface` unset and another surface available, the interview prints one line naming the default and the alternatives, then goes on with round 1 (#12658).

### Changed

- `interview`: the skill picks its lane through the registry instead of its own lane table, and the `share` action passes `share` to it. A configured surface whose tools are missing stays chosen and takes its spoke's degrade, as before. The page server skips the repository file's `surface` key without a note (#12658).
