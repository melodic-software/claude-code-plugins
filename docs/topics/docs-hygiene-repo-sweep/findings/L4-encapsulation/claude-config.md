# L4 encapsulation. Leaked skills in `plugins/claude-config`

1 violation, skill-to-skill inside the plugin.

**Owning skill:** `claude-config:audit-instructions` (`plugins/claude-config/skills/audit-instructions/`).
**Private surface reached:** `reference/criteria.md`.
**Leak kind:** private subdir.
**Citing file:** `plugins/claude-config/skills/audit/reference/audit-checklist.md:195`.

## V-cc-01

Verbatim:

```text
([`../../audit-instructions/reference/criteria.md`](../../audit-instructions/reference/criteria.md),
```

`plugins/claude-config` ships ten skills, several of which audit overlapping surfaces. A checklist
inside `claude-config:audit`'s reference tree pointing sideways into `claude-config:audit-instructions`'s
reference tree makes the two skills a single unit that cannot be split or reordered independently,
which is the failure mode the contract exists to prevent.

**Public surface element:** `/claude-config:audit-instructions`.

**Replacement text:**

```text
(`/claude-config:audit-instructions`,
```

## Judgment note

`reference/criteria.md` is the most-cited private file in the whole corpus once legal cites are
counted: `docs/adr/0004`, `0005`, `0006`, `0007`, `0008`, and
`docs/topics/context-engineering-claude-5/PLAN.md` all name it. Every one of those is a decision
record or a work plan narrating what it inspected, so all of them classify as KIND-1 meta-prose and
none is counted here. That concentration is still worth naming: the criteria catalog is behaving like
a repo-level artifact while living inside one skill's private body.

If the reconciliation pass wants a durable fix rather than a single-cite repair, the **Path A**
target is a repo-level instruction-audit catalog under `docs/conventions/`, which would also settle
the cross-plugin cite recorded as V-ct-01 in `code-tidying.md`. That is a larger move than this lane
should make on one violation; recorded here as the option, not the recommendation.

## Legal hits noted for the record, not counted as violations

- `docs/adr/0004:24`, `0004:331`, `0005:226`, `0006:48`, `0007:95`, `0008:21` and
  `docs/topics/context-engineering-claude-5/PLAN.md:417`. KIND-1 meta-prose: decision records and
  work plans citing evidence they weighed. They go stale rather than break, and nothing reads them to
  do work.
- `docs/topics/context-engineering-claude-5/design/checks-and-sweep.md:440` cites
  `skills/audit/context/validation-categories.md:110` as a quoted assertion under review. Same
  classification.

## Cross-lane observations

- L3 (SSOT): the ADR cluster above suggests `criteria.md`'s evidence tiers are restated across
  several decision records. That is L3's call, not this lane's.
