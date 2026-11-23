---
bump: minor
---

### Changed

- Bundled review criterion "Fail a change that loosens a check": a `## Loosened checks` section in
  the pull request body now gives a reason for loosening an ordinary check (tests, lint, coverage,
  type checks, scanners, validators, CI jobs). The section names each loosening and why the change
  needs it, and the reviewer judges whether that reason holds; a loosening the section omits, or
  whose reason does not hold, still fails. A security control or a billing hold keeps its stop
  whatever the section says, and the trusted spec issue still gives a reason as before. A loosening
  the section allows needs no decision-record citation.
- `/review:quality-gate`, `/review:fanout`, the `code-reviewer` agent and the `/review:code-review`
  CI lane hand reviewers that section beside the spec. The `review:fanout-sweep` workflow takes it
  as the new `loosenedSection` arg, keeps it only when it starts with the `## Loosened checks`
  heading, and cuts it at the next level-two heading so no other part of the body reaches a leaf.
