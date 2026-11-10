---
bump: minor
---

### Added

- `/planning:interview`: a `domain_docs` setting in `docs/conventions/planning.yaml` (`auto` default, `ask`, `off`) decides whether an engineering interview writes the glossary and proposes ADRs.
- `/planning:interview`: a scenario comparison (scenarios as rows, candidate terms or models as columns, then where each helps, makes no difference and costs) is offered when candidates compete, or on request.

### Changed

- `/planning:interview` question layout: the `Inference:` line is folded into the recommendation's reason, and `Checked against:` and `Flips if:` appear only when they carry something.
- The interview's own text says "interview" where it said "grilling"; "grill me" still reaches the skill.
