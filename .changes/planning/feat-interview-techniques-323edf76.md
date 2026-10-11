---
bump: minor
---

### Added

- `/planning:interview` recommends `/planning:questionnaire` at handoff for a deferred question only a named person other than the user can answer (an assumption-sweep `person` item), beside the usual next step. The new `interview-person-deferred-questionnaire` eval case grades it.
- Seven eval cases for interview behaviors not yet in the skill (per-answer read-back of a dictated answer, an active final confirmation, a changes-only final restatement, a checkable basis and flip condition per recommendation, the "something else" closing probe, a MoSCoW scope cut before `/planning:wayfind`, and one crux question on a rejected recommendation). Each rule lands only if its case fails without it.
