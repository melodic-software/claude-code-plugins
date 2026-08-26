# L7 findings: `H-knowledge-research`

Slice audited: 112 `AGENT` rows (32 `T2`). Predicates emitted here: P3.

Verbatim source quotes and proposed replacements are in fenced `text` blocks so wave 3 can match
them against the real files.

## P3 · pointer does not front-load the leading word

### H-1 · `plugins/discovery/skills/research/SKILL.md:159` (T2, S2)

Verbatim:

```text
See the discipline file's "Tool-ecosystem Phase 3 fallback" for the playbook.
```

This file cites `context/discipline.md` seven times and front-loads the matching term every other
time. Three of those, verbatim:

```text
The 30/14/90-day staleness windows: the discipline file's "Recency gate"
```

```text
top-down through the discipline file's artifact ladder
```

```text
Full recipe, why a criterion written afterwards drifts, and the exhaustive-surface table: the discipline file's "Corpus enumeration".
```

Line 159 is the single deviation, and it sits at the end of Path B where the reader has just been
told to cite three sources. Predicate: P3.

Replacement:

```text
Tool-ecosystem Phase 3 fallback playbook: the discipline file's "Tool-ecosystem Phase 3 fallback".
```

Severity S2: `T2` surface, routing only. The fix restores the file's own dominant pattern, so it is
low risk and needs no cross-lane coordination.
