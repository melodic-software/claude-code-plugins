---
bump: minor
---

### Added

- **`described_problem` setting: `report` (default) or `fix`.** With `fix`, `fable-5` treats a
  described problem as a request to fix it: it makes the change and presents the result. A question
  or thinking out loud still gets an assessment only, and a destructive or outward-visible step
  still waits for consent. It is set per user in the new `described_problem` user config option,
  and per repository in the `described_problem` key of `docs/conventions/playbooks.yaml`, which
  wins; the schema ships at `schemas/playbooks.schema.json` and the settings page at
  `reference/config.md`. The skill states which layer supplied the value, and an invalid value
  resolves `report`. The model-adaptation chapters do not read it.

### Changed

- **`fable-5` stages a shared-surface change only for consumers it cannot update.** The planning
  chapter's census no longer stages a surface because it has more than 10 consumers: staging (new
  shape beside the old, migrate, retire) is for external, unenumerable or persisted consumers, and a
  high internal count alone is not a reason, matching the execution chapter's rule on compatibility
  shims. A new eval case covers a large internal count. The implementation plugin's
  `refactor_compat` setting governs the same choice in refactor mode; an older implementation
  release has no option for it and ignores the repository key.
- **`skill-authoring` states the one-skill-per-call rule in its own words.** The rule is unchanged.
- **`skill-authoring` ends with a closing report.** The last reply of a run that creates or changes
  a skill lists the checks with their results (or not run), the choices made with their reasons,
  and what the skill does.
- **`skill-authoring`'s authoring guidance states the rule first.** An instruction says what to do,
  and gives its reason only where it would mislead without one; the degrees-of-freedom table no
  longer asks for a reason beside each high-freedom instruction.
