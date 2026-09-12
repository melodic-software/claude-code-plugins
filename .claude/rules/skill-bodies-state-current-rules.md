---
description: "Skill and agent bodies carry a four-part verification record for any volatile specific they restate, and name their successor in a `## Next` section; read before editing any skill body"
paths:
  - "plugins/*/skills/**"
  - "plugins/*/agents/**"
---

# Skill bodies state current rules

A pointer to an external upstream source (an official doc page, an upstream issue) is required
when a skill or agent body restates a volatile specific it cannot defer to at read time, recorded
as the four-part verification record the
[upstream-drift convention](../../docs/conventions/upstream-drift/README.md) defines: claim,
basis, as-of date, recheck trigger. A dated verification with a trigger is the correct form; an
undated claim is the defect.

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
