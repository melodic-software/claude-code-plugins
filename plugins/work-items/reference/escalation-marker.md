# Escalation marker: machine-readable comment grammar

Worker lanes escalate to the attended queue by pairing the human-gated role label with a
machine-marked HTML comment. `attend-queue` discriminates escalated rows from parked items wearing
the same role label by matching this prefix. A marker missing the `<!--` / `-->` wrapper does not
match.

## Comment prefix (first line)

```text
<!-- work-items:escalation lane=<lane> kind=<kind> -->
```

| Token | Values |
| --- | --- |
| `<lane>` | Lane id (`work-loop`, `attend-queue`, …) |
| `<kind>` | `escalated` \| `ratify-c3` \| `routed-advisory` |

## Writer / reader contract

1. Resolve the human-gated role label from `config.role_labels` (never a literal).
2. Post the marker comment (first line exactly as above, remainder is the human-readable question).
3. Apply the role label in the **same** label edit as any label removals the outcome requires.

## Proposed work class (optional body line, `kind=escalated`)

When a lane that may not record a class escalates an item for class stamping
(`/work-items:triage`'s "Lane barred from recording a class" branch), the comment body carries
one line of the form

```text
Proposed work class: <label>
```

where `<label>` is exactly one live `work-class:` label string as the repository spells it (for
example `work-class: scoped`), followed by its one-line basis. It is a proposal for
the operator, never an admission input: `attend-queue` reads it to pre-fill the stamp question,
and no consumer admits, dispatches, or merges on it. The marker `kind` stays `escalated`.

`attend-queue` matches on author **and** marker prefix. Suppress duplicate markers from the same
write identity, never from marker text alone.

Loop-lane escalation record files (`.claude/lane-escalations/…`) are optional exhaust; the tracker
item plus marker comment is the escalation of record when the record write fails.
