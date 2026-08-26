# L7 findings: `B-cc-config-ops`

Slice audited: 115 `AGENT` rows (29 `T2`). Predicates emitted here: P3, P7.

## P3 · pointer does not front-load the leading word

### B-1 through B-4 · `plugins/claude-ops/skills/audit-install-state/SKILL.md` (T2, S2)

Four phase sections each close with a bare `See <link>.` sentence. The reader decides whether to
open the target from the pointer text alone, and the pointer's first word is a routing verb, so the
matching term arrives only inside the filename.

| # | Line | Verbatim | Replacement |
|---|---|---|---|
| B-1 | 152 | `See [reference/surfaces.md](reference/surfaces.md).` | `Per-path retention rules: see [reference/surfaces.md](reference/surfaces.md).` |
| B-2 | 170 | `See [reference/name-schemes.md](reference/name-schemes.md).` | `Name schemes and their liveness meanings: see [reference/name-schemes.md](reference/name-schemes.md).` |
| B-3 | 205 | `See [reference/evidence-discipline.md](reference/evidence-discipline.md).` | `Cross-review procedure: see [reference/evidence-discipline.md](reference/evidence-discipline.md).` |
| B-4 | 213 | `See [reference/evidence-discipline.md](reference/evidence-discipline.md) §6.` | `Upstream-claim verification: see [reference/evidence-discipline.md](reference/evidence-discipline.md) §6.` |

Predicate: P3, "Front-load the leading word."

The same four pointers also fail P4 (cover the branches): none states what the reader gets by
following. P4 is routed to `L2-progressive-disclosure`'s blind-pointer shape, so the replacements
above supply only the leading term. If L2 files the same lines, take L2's fuller rewrite and drop
these four rows rather than applying both.

## P7 · a step defers a fact it needs to an unnamed location

### B-5 · `plugins/claude-config/skills/audit/SKILL.md:90` (T2, S2)

Verbatim:

> before the table below.

Full sentence, lines 88 to 90:

> Record the installed Claude Code version (`claude --version`). Phase 3.2 compares issue-fix
> versions against it. Then run `bash "${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/check-structure.sh"`
> before the table below.

The referenced table is the `### 1.2 Structure inventory` table at line 125, thirty-five lines and
two subsections away, with two other tables in the file above and below it. "The table below" does
not resolve during execution. Predicate: P7, "Distance a reader must jump during execution is a
defect."

Replacement for line 90:

> before filling the `1.2 Structure inventory` table.

Severity S2: `T2` surface, and an agent that fills the wrong table runs the phase out of order.
