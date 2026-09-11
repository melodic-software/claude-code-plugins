---
description: "Skill and agent bodies state the current rule and its reason, never the incident, PR, or model that motivated it, and name their successor in a `## Next` section; read before editing any skill body"
paths:
  - "plugins/*/skills/**"
  - "plugins/*/agents/**"
---

# Skill bodies state current rules

A skill body is read by the model on every invocation. Its authority is the behavior it
prescribes, not the incident that motivated it, so the body carries the rule and the reason and
nothing about how the rule got there. This follows the bundled `/claude-api prompt-audit` guide
(Group 2, "Brittle skill files").

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

The platform skill-authoring guidance recommends the opposite shape for superseded guidance: an
in-body "Old patterns" section inside a collapsed `<details>` block
([content guidelines](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#content-guidelines),
verified 2026-09-10). This repository deviates on purpose: every body line is a recurring token
cost on invocation, so history routes to the CHANGELOG, the commit, and `docs/adr/`, and a volatile
specific carries the four-part record above instead of a legacy stanza. Recheck this paragraph when
that page drops or changes the "Old patterns" recommendation.

## Successor sections

A skill that has a natural successor names it in a `## Next` section placed before `## Gotchas`
(or before the last H2 when the file has none). The heading is exactly `## Next`. The body is
either one `/plugin:skill` invocation on a line, with any arguments that skill takes, optionally
followed by a sentence that names what the successor consumes or why it is next; or two to four
bullets of `<outcome>: /plugin:skill [args].` when the successor depends on the run's result. It
is a mention for the human, never an operative chain, so it carries no Skill-tool phrasing, no
installed-ness gate, and no fallback clause. Keeping the graph current is authoring work:

- A new skill writes its own `## Next` and edits the predecessor whose `## Next` should now name
  it.
- A renamed skill is swept with `/docs-hygiene:rename-references audit` (when that plugin is
  installed; otherwise grep the old token).
- A removed skill's token is grepped and every `## Next` that carried it is edited.
- `/session-flow:workflow` owns stage routing. A `## Next` states the typical successor; when the
  two disagree, the workflow skill's ladder wins.
