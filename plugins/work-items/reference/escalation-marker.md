# Escalation marker — machine-readable comment grammar

Worker lanes escalate to the attended queue by pairing the human-gated role label with a
machine-marked HTML comment. `attend-queue` discriminates escalated rows from parked items wearing
the same role label by matching this prefix — a marker missing the `<!--` / `-->` wrapper does not
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

`attend-queue` matches on author **and** marker prefix — suppress duplicate markers from the same
write identity, never from marker text alone.

Loop-lane escalation record files (`.claude/lane-escalations/…`) are optional exhaust; the tracker
item plus marker comment is the escalation of record when the record write fails.
