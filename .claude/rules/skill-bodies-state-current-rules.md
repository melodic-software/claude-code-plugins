---
description: "Skill and agent bodies point at the live upstream source for any volatile specific instead of restating it, recorded as our decision plus a section-anchored pointer (an as-of date and recheck trigger only on a copied or measured upstream number or string), name their successor in `## Next` and context-dependent links in `## Related`, and mark optional-plugin mentions `(if enabled)`; read before editing any skill body"
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
[upstream-drift convention](../../docs/contracts/upstream-drift/README.md#required-parts)
defines: our decision and a pointer to the exact section or issue, with the situation in which to
fetch it where that helps. A pointer carries no as-of date and no recheck trigger: the link checks
catch a dead link or moved anchor, and whoever fetches the link reads its current content. A body
that needs the specific at run time fetches it from the pointer.

A stored value is a number or string copied or measured from upstream: a default, limit, version
gate, price, error string, measured figure (bytes, milliseconds, a hash, a count, with the version
it was measured on), or pinned SHA. Described or observed behavior with no recorded number or
string, a "no docs page covers X" note, a source conflict and a "last researched" date are
pointers. `scripts/check-as-of-recheck.sh` fails a paragraph holding an as-of date and no recheck
trigger, and names the fix: the trigger for a stored value, no date for a pointer.

A record never cures a restatement: restated text with an as-of stamp or `Claim/Basis` block
beside it is still the defect, fixed by deleting the restated value and keeping the pointer. Older
`Claim/Basis` records in nearby files are not precedent (#5684 converts them). The record is also
defective when a docs-page pointer lacks the section anchor (an upstream issue or probe needs
none), a blog post is the pointer where a docs section covers the topic (it goes beside the
pointer as a "correlate with" note), a probe observation names no probe, or a stored value lacks
its as-of date.

## Successor sections

Each routing job has one place. Every skill token in any of them is written `/plugin:skill`, with
the slash.

| Place | Job | Shape |
| --- | --- | --- |
| frontmatter `description` | picking the skill (the only text in context before it runs) | when to use; a confusable neighbor as `Not for <case>: /plugin:skill` |
| `## Next` | after the run, chosen by its result | see below |
| `## Related` | depends on the reader's situation, not the result | bullets `<condition>: /plugin:skill [args].` |
| `## See also` | files to read | links only, never a skill |
| `## What this skill does not do` | scope exclusions in the body | bullets; one that steers selection also goes in the description as `Not for` |
| steps | a skill the run really invokes as a step | stays in its step |

`## Next` sits before `## Gotchas` (or before the last H2 when the file has none). Its body is
either:

- one line, `/plugin:skill [args]`, optionally followed by one sentence, when the successor is
  the same every time; or
- two or more bullets `<result>: <target>.`, each naming one target. A target is
  `/plugin:skill [args]` or `the <stage> stage (/plugin:skill)`, where the skill is that stage's
  entry skill in `plugins/session-flow/skills/workflow/reference/stages.yaml`. No chain ("X, then
  Y"), no bullet routing an unsure reader to `/session-flow:workflow`, no fixed maximum.

At the end of a run the model offers the one bullet matching the result ("Next: /x:y, because
..."), and never runs it unasked. A skill's `## Next` wins over the workflow ladder; the ladder is
the fallback when no bullet matches. `## Next` and `## Related` carry no Skill-tool phrasing, no
availability gate and no fallback clause; a standalone skill carries neither. A link may name a
user-only skill; the model presents it as the user's own line to run.

Other routing headings (Boundaries, Siblings, Routing, Handoff, Composition, Integration) fold
into these places: a suggestion into `## Next` or `## Related`, an exclusion into `## What this
skill does not do`, an operative step into the steps.

Keeping the graph current is authoring work, checked by `scripts/check-next-graph.py` (run
`--fix` to rewrite stage targets from the map, `--fix --renames <file>` after a rename):

- A new skill writes its own `## Next` and edits the predecessor whose `## Next` should now name
  it.
- A renamed or removed skill's token is swept with `/docs-hygiene:rename-references audit` (if
  enabled; otherwise grep the old token).
- A `## Next` edge to an earlier stage, or past a stage the map never skips, is declared in the
  map's `loop-backs` or `skips` with its reason.

## Optional-plugin mentions

Outside `## Next` and `## Related`, a skill body mentions an optional plugin's skill as
"`/plugin:skill` (if enabled)", followed by "; otherwise" and the fallback when one exists. This is
the wording of the guard rule in [plugin philosophy](../../docs/plugin-philosophy.md#design-boundary).
`## Next` and `## Related` are exempt: they carry no availability gate.
