# L2 progressive disclosure: `F-quality-verify`

121 files, 31 `T2`. Plugins: `bugs`, `codebase-health`, `debugging`, `evals`, `mutation-testing`,
`review`, `tdd`, `testing`, `verification`.

Totals: T1=5, T2=3, T3=1.

## Split lane

One `T2` body in this group crosses either ceiling. The next largest,
`plugins/debugging/skills/debug/SKILL.md` at 192 lines / 2,790 words, is comfortably inside both,
and the small-corpus guard covers the rest.

### `oversize` + `tier-mismatch`: `plugins/mutation-testing/skills/audit/SKILL.md` (Tier 2)

406 lines, 4,360 words, 2 `context/` spokes.

Two separable blocks:

`plugins/mutation-testing/skills/audit/SKILL.md:122`:

> `## Phase 3 — Execute`

Lines 122 to 194, 73 lines, the runner mechanics.

`plugins/mutation-testing/skills/audit/SKILL.md:251`:

> `## Mutation audit — <scope>, vs <diff-target>`

Lines **251 to 293, 43 lines**, an H2 that is not a phase at all: it is the report template, with
`### Survivors`, `### Suppressed`, `### Suppressions that did NOT apply`, `### Proposed
suppressions`, and `### Unclassified` as its sub-sections. Template content is on-demand artifact
shape, not hub content, and its H2 sits at the same level as the phases so a reader scanning the
outline sees a phantom phase between Phase 5 and Phase 6.

**Split spec.**

New spoke: `plugins/mutation-testing/skills/audit/templates/report.md`

Moves: lines 251 to 293 verbatim, the H2 promoted to H1 `# Mutation audit report template` and its
five H3s kept as H2s.

Replaces lines 251 to 293 with a pointer folded into Phase 5, which currently ends at line 250:

```markdown
Write the report from [`templates/report.md`](templates/report.md). Read it at the start of Phase
5, before assembling any section: it owns the heading order, the five result classes, and what
each row must carry. Phase 6 persists whatever Phase 5 wrote, so a section invented here is a
section persisted.
```

Second split, same file. New spoke:
`plugins/mutation-testing/skills/audit/context/execute.md` holding lines 123 to 194. Replaces
lines 122 to 194 with:

```markdown
## Phase 3 — Execute

Read [context/execute.md](context/execute.md) before the first mutant run: it owns the runner
invocation per ecosystem, the timeout and incremental-run rules, the crash and no-coverage
dispositions, and the artifact paths Phase 4 reads. Phase 2's generated mutant set is its only
input.
```

Resulting `SKILL.md`: 406 - 43 - 72 + 14 = **305 lines**.

## Structure lane

### `missing-toc` (Tier 1)

| Path | Lines |
|---|---|
| `plugins/review/skills/quality-gate/context/close-out.md` | 415 |
| `plugins/mutation-testing/skills/audit/context/persist-findings.md` | 358 |
| `plugins/tdd/skills/principles/reference/testing-styles-khorikov.md` | 354 |
| `plugins/tdd/skills/principles/reference/integration-testing-khorikov.md` | 352 |
| `plugins/tdd/skills/principles/reference/test-design.md` | 307 |

The three `tdd/skills/principles/reference/` files are the sharpest as a set: they are alternates
that a reader picks between (unit-test styles, integration testing, test design), so a reader
arrives having already decided which file, then needs to reach one idea inside it.

Remediation, all five: insert a `## Contents` anchor list under the H1, matching
`plugins/docs-hygiene/skills/audit-progressive-disclosure/context/tier-model.md:3-9`.

### `blind-pointer`: `## Cross-references` with no load condition (Tier 2)

| Path:line | Verbatim heading |
|---|---|
| `plugins/bugs/skills/scan/SKILL.md:237` | `## Cross-references` |
| `plugins/bugs/skills/write/SKILL.md:140` | `## Cross-references` |

Sample rows, `plugins/bugs/skills/scan/SKILL.md:243-245`:

```text
- [`context/findings-report.md`](context/findings-report.md). Report format, evidence labels, refuted
- [`${CLAUDE_PLUGIN_ROOT}/reference/config.md`](../../reference/config.md). `.claude/bugs.md`
```

Each row states what the target holds and not when to open it. Note that `scan`'s in-body pointers
are good: line 133 (`[`context/lenses.md`](context/lenses.md). Size the fan-out to the surface`)
and line 143 both carry the condition. Only the trailing index section is blind.

Remediation, both files: rename the heading to `## Reference index. Load on demand` and append a
when-clause to each row. For the sampled rows:

```markdown
- [`context/findings-report.md`](context/findings-report.md). Read before emitting the first
  finding: report format, evidence labels, the refuted tail, and the cut rules.
- [`${CLAUDE_PLUGIN_ROOT}/reference/config.md`](../../reference/config.md). Read when a
  `.claude/bugs.md` key is present that the flow above does not name: the key set, the layers,
  and the merge semantics.
```

### `missing-toc`, 100 to 300 lines (Tier 3, awareness only)

30 files. No treatment.

## Cross-lane observations

- `plugins/mutation-testing/skills/audit/context/persist-findings.md` and
  `plugins/review/skills/quality-gate/context/close-out.md` both specify a findings-persistence
  artifact against `docs/conventions/detector-findings/README.md`. L3.
- `plugins/codebase-health/skills/audit/templates/checklist.md`,
  `plugins/debugging/skills/debug/templates/checklist.md`, and the other `templates/checklist.md`
  files across the corpus share a shape. L3.
