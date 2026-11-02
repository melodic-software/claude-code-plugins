---
bump: minor
---

### Added

- `/harness-ops:changelog apply --ci <release|range>` runs `apply` with nobody to answer. Only a cited, verified `correct` row confined to one owner plugin and not security-relevant is committed, on a local `changelog/<plugin>/v<range>` branch per owner plugin; every other row becomes a handoff. It asks nothing, pushes nothing, opens no pull request, files nothing and never moves the read marker, and writes `ci-plan.json` (branches with base and head commits and PR title and body, handoffs with dedupe keys) for the calling workflow. The rule and the plan format are in the skill's `context/ci-mode.md`.
- Two eval cases: `cl-ci-cap-exceeded-stops` and `cl-ci-adopt-is-handoff`.
