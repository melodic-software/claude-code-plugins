---
bump: minor
---

### Added

- **`attended`, separate from `host-run` and `needs-human`.** Work that needs the owner present (a manual step on external state an agent cannot safely run or test) gets the `attended` label. Intake admission refuses it as it refuses `host-run`, parked at `status: confirmed` with no decision asked. While the newest `attended` event is a removal by anyone but a listed human, the lanes App included, admission refuses as if the label were on.
- **External state in refinements.** An exact intake refinement ends its criteria with one plain line, `External state: none`, `iac (<owner/repo>)` or `manual (<class>: <what>)`. Admission refuses a `manual` one and adds `attended`, until a listed human removes `attended` after that refinement; `iac` routes nothing. The classes are config: the new `attended.classes` section of `pr-pipeline.yaml`, which `refine.mjs --select` puts in the model's context and `--apply` checks.
- **`attended` holds downstream.** work-unblock never adds `agent-ready` to an issue carrying `attended`, or to an admission-deferred one whose newest `attended` event is a removal by anyone but a listed human; its re-admission paths park an attended refusal at `status: confirmed` with `attended`. resolve-issue and apply-issue-patch hold on `attended`.
- **`manual-external` stop code.** A resolve-issue run that reaches such a step stops with `manual-external`, whose new `attended` route adds the label and removes `agent-ready`; `host-only` now names a host run alone.
