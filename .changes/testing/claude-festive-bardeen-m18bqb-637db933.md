---
bump: minor
---

### Added

- A `LICENSE` carrying the MIT notice for content reauthored from emilkowalski/skills (pinned in `docs/upstream/emilkowalski-skills.md`) beside the Melodic Software derivative line.
- `/testing:run-e2e worst-case [--keep] <target>`: renders a component or screen with plausible worst-case data (long and short names, unbreakable strings, extreme numbers, empty and huge collections, missing media, every state) injected at the data boundary, network mocking first, in narrow, wide, zoomed, dark and right-to-left environments, and reports what broke, the decisions for the user and what held up. A file it injects is backed up and reverted, and the revert is proven by comparing `git diff` and full `git status` snapshots with `cmp`; a dirty target file is refused. `--keep` keeps the fixture as a regression test, and `.claude/testing/worst-case.md` extends the catalog.
