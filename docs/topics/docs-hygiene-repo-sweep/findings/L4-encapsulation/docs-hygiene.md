# L4 encapsulation. Leaked skills in `plugins/docs-hygiene`

1 violation. The leaked skill belongs to the same plugin that owns this lane's rubric, which is worth
stating plainly rather than quietly exempting.

**Owning skill:** `docs-hygiene:write-for-humans` (`plugins/docs-hygiene/skills/write-for-humans/`).
**Private surface reached:** `reference/sources.md`.
**Leak kind:** private subdir.
**Citing file:** `docs/conventions/upstream-drift/README.md:343`.
**Confidence:** medium. This is a registry row recording where a set of conforming upstream-drift
records lives, not a content dependency. It is reported because the row is a live index: a
`write-for-humans` refactor turns it into a dangling link with nothing failing.

## V-dhg-01

Verbatim (leading cell of a long table row; the rest of the row is unchanged):

```text
| [docs-hygiene `write-for-humans` source records](../../../plugins/docs-hygiene/skills/write-for-humans/reference/sources.md) | new with docs-hygiene 0.18.0 |
```

**Public surface element:** `/docs-hygiene:write-for-humans`, plus the record set's own name. The
registry's job is to say that a conforming record set exists and what shape it has; naming the
skill does that without pinning the file.

**Replacement text (leading cell only):**

```text
| `/docs-hygiene:write-for-humans` source records | new with docs-hygiene 0.18.0 |
```

## Same shape as V-slop-02

`docs/conventions/upstream-drift/README.md:342` carries the identical shape against
`ai-slop:audit`'s `reference/catalog.md` and is recorded as V-slop-02 in `ai-slop.md`. Both rows are
in the same table. If the reconciliation pass prefers a structural fix over two cell rewrites, the
option is to give the upstream-drift registry a stable way to address a record set that lives inside
a skill: a named record id per row, resolved by the owning skill, rather than a path. That is a
convention change and belongs to the convention's owner, not to this lane. Recorded, not
recommended.

## Legal hits noted for the record, not counted as violations

`docs/conventions/upstream-drift/README.md:150` cites
`plugins/claude-ops/skills/changelog/context/read-actions.md` inside a narrative about where a rule
was hoisted from ("carried it page-scoped ..."). KIND-1 meta-prose: historical narrative. It goes
stale rather than breaking.

## Cross-lane observations

- This lane audits its own plugin's skills on the same rubric as every other plugin's. No exemption
  was applied, and none is warranted: the contract binds the skill that publishes it.
