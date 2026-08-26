# Mutation audit report template

The artifact Phase 5 of [`../SKILL.md`](../SKILL.md) writes, and the one Phase 6 persists verbatim
under `--persist-findings`. Copy the skeleton below rather than inventing sections: a section
invented at report time is a section persisted.

```text
## Mutation audit — <scope>, vs <diff-target>

Baseline: <green, N ms>   Mutants: <n> generated, <n> suppressed<, n dropped by cap>

| File | Coverage | Covered-code score | Gap | Survivors |
|---|---|---|---|---|

### Survivors
| File:line | Operator | Mutation | Disposition | Why |
|---|---|---|---|---|

### Suppressed
| finding_id | Site | check / claim | Reason | Date | Layer |
|---|---|---|---|---|---|

### Suppressions that did NOT apply
<each `personal-only, not applied` entry, naming promotion to the team layer as the remedy;
each malformed entry, naming which required key is missing or that its constituents do not
hash to its key; each stale entry whose finding is gone or whose operator was retired>

Not examined this run: <n> entries whose anchored nodes fell outside the scope above
(counted at node granularity — an entry in a file this run touched elsewhere still counts here).

### Proposed suppressions
<complete entries for arid survivors — all five keys with the id derived from them — for the
user to accept>

### Unclassified
<survivors whose withholding claim could not cite evidence — arid or equivalent, named with which
was claimed and what was missing>
```

The two suppression sections are obligations of the finding-suppression contract, not report
garnish: a suppression the operator wrote that the contract **declined to enact** is exactly as
important to show as one that applied, and provenance per entry is what distinguishes a team floor
from a personal draft.
