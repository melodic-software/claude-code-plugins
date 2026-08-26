# L4 encapsulation. Leaked skills in `plugins/session-flow`

1 violation, and it is in a repo-level convention doc, which puts it in the same severity band as the
`review/fanout` cluster even though it is a single cite.

**Owning skill:** `session-flow:workflow` (`plugins/session-flow/skills/workflow/`).
**Private surface reached:** `context/pre-pr.md`.
**Leak kind:** private subdir.
**Citing file:** `docs/conventions/pre-pr-ordering/README.md:5`.

## V-sf-01

Verbatim (lines 4-7 of the citing file, with the cite on line 5):

```text
**order**; it does not own the checklist. `session-flow`'s
[`workflow/context/pre-pr.md`](../../../plugins/session-flow/skills/workflow/context/pre-pr.md)
is the human-facing sequence that implements this order, and remains the place to read *what*
each step does.
```

The convention doc is explicit that more than one plugin routes into this ordering, and it hands the
reader a private path as the place to read what each step does. Every plugin that adopts the
convention therefore inherits a dependency on `session-flow:workflow`'s internal file layout.

**Public surface element:** `/session-flow:workflow`. The citing sentence says the target is "the
human-facing sequence that implements this order", which is behavior the skill performs, not a
document only this convention needs.

**Replacement text (line 5, and the trailing words of line 4 to keep the sentence grammatical):**

```text
**order**; it does not own the checklist. `/session-flow:workflow`
is the human-facing sequence that implements this order, and remains the place to read *what*
each step does.
```

## Judgment note. Route, not promote

The tempting Path A here is to promote the pre-PR checklist into the convention directory. Resist it:
the convention doc says in its own first paragraph that it owns the **order** and not the checklist,
and the split is deliberate. Promoting the checklist would merge two things the doc separated on
purpose. Route is the fix.

## Cross-lane observations

- L1 (derivability): `docs/conventions/pre-pr-ordering/README.md` is a thin owner doc whose stated
  reason for existing is that a second plugin adopted an ordering. If L1 proposes converting it to a
  pointer, this violation moves with it. Re-resolve before applying.
- L2 (progressive disclosure): if L2 splits `skills/workflow/context/pre-pr.md`, the route-form
  replacement above is unaffected, which is the point of routing rather than re-pointing.
