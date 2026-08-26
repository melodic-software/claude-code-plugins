# G-code-design

Lane `L8-write-for-humans`, wave 1, read-only. Audience slice: 16 `HUMAN` rows (8 plugin READMEs,
8 CHANGELOGs). The 8 CHANGELOGs are judged as a class in `README.md`.

Low yield. Two `L1` findings, no mode findings, no ambiguity findings.

## Findings

| # | Path | Predicate | Severity |
|---|---|---|---|
| G1 | `plugins/naming/README.md:14` | `L1` | S2 |
| G2 | `plugins/overengineering/README.md:149` | `L1` | S3 |

### G1

`plugins/naming/README.md:14`, 45 words, 3 interrupters. Verbatim:

```text
So the generators run BLIND to the conversation, seeded only with a structured context brief (responsibility, firing context, scope boundaries, collision vocabulary, word-level blocklist; rejected NAMES stay on the main thread's reject list, never in the brief), each working a distinct lens (responsibility-literal, moment-of-use, domain-lore).
```

Predicate `L1`. The parenthetical carries a five-item list and then, after a semicolon, an unrelated
rule about where rejected names live. Two thoughts in one parenthesis.

Also `Am4`: `seeded only with a structured context brief` places `only` before the whole predicate,
where what it modifies is the brief. As written it can be read as "the only thing they are seeded
with is a brief" (the intended reading) or "they are merely seeded, not otherwise fed" (not
intended). Moving `only` next to `a structured context brief` settles it.

Replacement:

```text
So the generators run BLIND to the conversation. Each is seeded with only a structured context
brief: responsibility, firing context, scope boundaries, collision vocabulary, and a word-level
blocklist. Rejected NAMES stay on the main thread's reject list and never enter the brief. Each
generator works a distinct lens: responsibility-literal, moment-of-use, or domain-lore.
```

### G2

`plugins/overengineering/README.md:149`, 47 words, 3 interrupters. Verbatim:

```text
That queue is always in the report; **routing it durably to a work-item tracker is opt-in**, because a tracker that refuses to file on inferred intent needs an authorization an unattended cycle has nobody to give, and the operator setting `filing_posture` in tracked config is that authorization.
```

Predicate `L1`, filed at S3 because the sentence is long but linear: the reader does not have to
backtrack, only to hold one clause open. The resolved guide's rhythm rule explicitly protects a long
sentence that carries one thought, and this one arguably does.

No replacement supplied. Wave 3 may split at `and the operator setting` if it is already in the file
for another reason, or leave it. This is the boundary case for the `L1` filter and it is recorded
rather than prescribed.

## Document mode

Eight plugin READMEs, all reference with an explanation lead, all holding one mode. No mode
findings.

`plugins/overengineering/README.md:75` was read closely because it carries an opinion inside what
looks like reference. Verbatim fragment:

```text
A shallow clone makes history *unavailable* rather than silent, and the report leads with an evidence-availability assessment naming which tiers exist here at all, because that changes what UNPROVEN means for every row beneath it.
```

Not a finding. The section is explanation, explanation is the one mode that permits a view, and the
resolved guide's register gate protects an author's voice in a narrative section. Flattening this
into a neutral list is the skill's own third gotcha ("the usual way a good design document dies").
Recorded so wave 3 does not do it.

## Predicates with no findings in this group

`M1`, `M2`, `M3`, `A1`, `A2`, `Am1`, `Am2`, `Am3`, `N1`, `C1`.

On `M3`: every plugin README in this group that carries a generated options block has it under
`## Configuration`. Fully conformant.

On `M2`: `plugins/overengineering/README.md:6` and `plugins/improvement/README.md:64` both contain
`no longer` and `previously`. Both are describing what the skills detect, not this repo's release
history. Not findings.

## Cross-lane observations

- **`ai-slop:audit`**: nothing in this group's READMEs.
- **`source-control`**: nothing in this group.
