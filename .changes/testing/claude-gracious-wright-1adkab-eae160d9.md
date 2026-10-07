---
bump: minor
---

### Added

- **Browser-tools benchmark** under `benchmarks/browser-tools/`: tool-neutral fixture pages for modern server-rendered and hydrated UI behaviors, twelve agent tasks drawn from the development flow (self-check, outcome verification, PR evidence, exploratory testing, logged-in session, untrusted page content), CDP reference solutions that prove every grader, a scripted no-model layer, an agent layer with a clean `claude -p --bare` runner, and an aggregator applying a pre-registered win rule. First results (2026-10-07) compare agent-browser 0.38.2 with `@playwright/cli` 0.1.22.
