---
bump: major
---

### Removed

- **The three Loosened checks keys are gone** from the schema and from
  `reference/config-resolution.md`: the heading, record pattern and verbatim marker keys that
  the guardrails PR-body hook read. A team file that still sets one fails schema validation;
  delete those lines. pr-verify alone judges a `## Loosened checks` section, by the review
  plugin's loosened-check rule ([#19312](https://github.com/melodic-software/claude-code-plugins/issues/19312)).
