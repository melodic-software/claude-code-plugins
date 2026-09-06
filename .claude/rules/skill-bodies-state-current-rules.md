---
description: "Skill and agent bodies state the current rule and its reason, never the incident, PR, or model that motivated it; read before editing any skill body"
paths:
  - "plugins/*/skills/**"
  - "plugins/*/agents/**"
---

# Skill bodies state current rules

A skill body is read by the model on every invocation. Its authority is the behavior it
prescribes, not the incident that motivated it, so the body carries the rule and the reason and
nothing about how the rule got there. This follows the bundled `/claude-api prompt-audit` guide
(Group 2, "Brittle skill files"), applied fleet-wide in the 2026-09 audit recorded in
[`docs/specs/prompt-audit-skills-2026-09.md`](../../docs/specs/prompt-audit-skills-2026-09.md).

Keep out of a skill or agent body:

- Issue and pull-request numbers from this repository, incident IDs, and past-tense narration of
  why a rule exists ("this was added after ...", "an earlier version claimed ...").
- Pinned model names in behavioral guidance. A rule that only holds on one model belongs in the
  `playbooks` model-adaptation chapters, not in a skill body.
- Date-conditional guidance ("before 2026-08 ...", "until version X ships ...").
- Hardcoded paths, flags, and version numbers stated as bare fact with no verification.

Keep in the body:

- The rule, stated in the present tense, with the reason beside it.
- A pointer to an external upstream source (an official doc page, an upstream issue) when the rule
  restates a volatile specific it cannot defer to at read time, recorded as the four-part
  verification record the
  [upstream-drift convention](../../docs/conventions/upstream-drift/README.md) defines: claim,
  basis, as-of date, recheck trigger. A dated verification with a trigger is the correct form; an
  undated claim is the defect.

History belongs in the plugin's `CHANGELOG.md`, the commit message, and `docs/adr/`. A reader who
needs the archaeology finds it there; the model reading the skill does not need it to act.
