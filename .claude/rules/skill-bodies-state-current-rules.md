---
description: "Skill and agent bodies point at the live upstream source for any volatile specific instead of restating it, recorded as pointer, as-of date and recheck trigger, and name their successor in a `## Next` section; read before editing any skill body"
paths:
  - "plugins/*/skills/**"
  - "plugins/*/agents/**"
---

# Skill bodies state current rules

A skill or agent body never restates a volatile upstream specific, quoted or paraphrased. Volatile
means an upstream page, issue or release can change it without our edit: product or tool behavior
given as our reason ("because WebFetch returns a summary", "the artifact stays private until
shared"), API availability ("thread resolution is GraphQL-only"), a limit, default, version,
error string, schema or benchmark figure. The body states our decision in our own words (it may
name the topic, never what the page says about it) and records where to read the specific live,
in the links-only record the
[upstream-drift convention](../../docs/conventions/upstream-drift/README.md#required-parts)
defines: pointer to the exact section, as-of date, recheck trigger. A body that needs the specific
at run time fetches it from the pointer.

A record never cures a restatement: restated text with an as-of stamp or `Claim/Basis` block
beside it is still the defect, fixed by deleting the restated value and keeping the pointer. Older
`Claim/Basis` records in nearby files are not precedent (#5684 converts them). The record is also
defective when the pointer lacks the section anchor, the trigger does not cover every cited
section, a blog post is the pointer where a docs section covers the topic (it goes beside the
pointer as a "correlate with" note), a probe observation names no probe, or the as-of date or
trigger is missing.

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
