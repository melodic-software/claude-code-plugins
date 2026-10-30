---
bump: minor
---

### Added

- `/planning:prd` gains a ninth required section, **Quality requirements**, in every tier template ([#8322](https://github.com/melodic-software/claude-code-plugins/issues/8322)). It takes its prompts from `/planning:interview`'s quality-requirement list and asks for a measurable target only where a wrong guess would change the design. A one-pager records only the prompts where the feature moves the product's current bar, a consumer feature covers every prompt it touches, and a B2B-internal PRD covers every prompt. Before, a PRD had no place for performance, reliability or security targets, so they first came up at interview or design time.
