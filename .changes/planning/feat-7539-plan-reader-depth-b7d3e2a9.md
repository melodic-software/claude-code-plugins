---
bump: minor
---

### Added

- `/planning:plan` publishes an approved plan at a reader depth: `step-by-step` (default, the whole PLAN.md), `standard` (the `## Brief`, the `## Design` section and a phase outline) or `guardrails` (the `## Brief` and the `## Design` section). The depth comes from a `--reader <depth>` argument, else the depth the plan recorded at its first publish, else the new `plan_reader` key in `docs/conventions/planning.yaml` or the plugin's user config, else `step-by-step`. A reduced depth renders a derived `PLAN.<depth>.md` that keeps the `Approval:` line and goes to `/work-items:track publish-plan` and the pull request paste; PLAN.md stays whole.
- PLAN.md's `### Conventions followed` carries a `Net new:` line and a `Challenges a pattern:` line, which `/planning:design-handoff` fills.
