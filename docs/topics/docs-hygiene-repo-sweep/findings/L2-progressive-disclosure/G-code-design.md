# L2 progressive disclosure: `G-code-design`

94 files, 17 `T2`. Plugins: `architecture`, `code-tidying`, `coupling`, `domain-driven-design`,
`event-storming`, `improvement`, `naming`, `overengineering`.

Totals: T1=7, T2=2, T3=1.

## Split lane

### `oversize` + `tier-mismatch`: `plugins/overengineering/skills/delta/SKILL.md` (Tier 2)

480 lines, **5,796 words**, one `context/` spoke. 96% of the line ceiling and 55% over the
recommended 5k-token body size, the largest word count in this group by a wide margin.

The body's 18 H2s split cleanly into procedure and explainer. Six sections are conceptual
reference, read once to understand the mechanic and never re-executed:

| Section | Lines | Span |
|---|---|---|
| `## The load-bearing mechanic: the baseline is the PREVIOUS cycle's post-audit spine` | 93 to 133 | 41 |
| `## The bootstrap cycle. The one pre-audit capture` | 134 to 148 | 15 |
| `## The spine baseline` | 149 to 170 | 22 |
| `## A detached checkout has no branch identity` | 237 to 269 | 33 |
| `## No baseline. A first-class state, not an error` | 270 to 288 | 19 |
| `## Layers that were not walked` | 289 to 307 | 19 |

149 lines, 31% of the file, none of it a step of `## The run` (lines 187 to 236). The rubric's
`tier-mismatch` shape names exactly this: reference detail inline in a hub, routed down-tier
behind a pointer.

`plugins/overengineering/skills/delta/SKILL.md:95`:

> `Two independent things have to be right here, and each fails silently on its own.`

**Split spec.**

Two new spokes under the existing `context/` directory:

- `plugins/overengineering/skills/delta/context/baseline-model.md`, holding lines 94 to 170 (the
  load-bearing mechanic, the bootstrap cycle, and the spine baseline, in that order), promoted to
  H1 `# The baseline model` with the three H2s preserved. Opens with a `## Contents` list.
- `plugins/overengineering/skills/delta/context/run-states.md`, holding lines 238 to 307 (detached
  checkout, no baseline, unwalked layers), promoted to H1 `# Run states that are not errors`.

Replaces lines 93 to 170 with:

```markdown
## The baseline: the PREVIOUS cycle's post-audit spine

The delta is computed against the previous cycle's post-audit spine, stored as
`spine-baseline.md` beside the findings artifact in the same resolved home. Read
[context/baseline-model.md](context/baseline-model.md) before the first run against a home you
have not seen this session: it owns the two things that must both be right, the bootstrap cycle
for a home with an artifact but no baseline, and the baseline file's frontmatter and fields. Both
failure modes are silent, so do not infer the model from the run steps below.
```

Replaces lines 237 to 307 with:

```markdown
## Run states that are not errors

A detached checkout, a missing baseline, a branch mismatch, and a layer the audit did not walk are
all first-class states with defined handling, not failures. Read
[context/run-states.md](context/run-states.md) whenever the run resolves into one of them: it owns
branch-identity resolution on a detached `HEAD`, the no-baseline disposition, and merge rule 4's
carry-forward for unwalked layers. Reporting any of these as an error is the defect this file
prevents.
```

Resulting `SKILL.md`: 480 - 149 + 22 = **353 lines**, and the file's remaining H2s are all run
steps or output contracts.

### Not findings

`plugins/overengineering/skills/realign/SKILL.md` (273 lines / 3,318 words),
`plugins/overengineering/skills/audit/SKILL.md` (274 / 3,126), and
`plugins/code-tidying/skills/tidy/SKILL.md` (229 / 3,155) are all inside both ceilings. The
small-corpus guard applies.

## Structure lane

### `missing-toc` (Tier 1)

| Path | Lines |
|---|---|
| `plugins/event-storming/skills/simulation/reference/agentic-simulation.md` | 1,023 |
| `plugins/overengineering/context/findings-artifact.md` | 521 |
| `plugins/overengineering/context/scrutiny-method.md` | 482 |
| `plugins/event-storming/skills/methodology/reference/big-picture-workshop.md` | 432 |
| `plugins/event-storming/skills/simulation/reference/simulation-evaluation.md` | 343 |
| `plugins/code-tidying/skills/batch-simplify/context/repo-mode.md` | 317 |
| `plugins/event-storming/skills/methodology/reference/design-level.md` | 311 |

`plugins/overengineering/context/findings-artifact.md` is the sharpest: the `delta` skill above
reads it to answer per-field questions about the artifact, which is a lookup access pattern with
no index at the target.

Remediation, all seven: insert a `## Contents` anchor list under the H1, matching
`plugins/docs-hygiene/skills/audit-progressive-disclosure/context/tier-model.md:3-9`. For
`findings-artifact.md`, make the list enumerate the artifact's fields.

### `deep-nesting` (Tier 2)

**`plugins/architecture/skills/improve/actions/deepening.md:26`**

> `Brief each scan subagent with the canonical template in [../research/deepening/scan-briefing.md](../research/deepening/scan-briefing.md)`

Five files under `plugins/architecture/skills/improve/research/deepening/` are reached only from
`actions/deepening.md`, which is itself a spoke of `SKILL.md`. Two hops for content the citing
lines mark as required:

| Target | Cited at | Wording |
|---|---|---|
| `research/deepening/scan-briefing.md` | `actions/deepening.md:26` | "Brief each scan subagent with the canonical template in" |
| `research/deepening/vocabulary.md` | `actions/deepening.md:35`, `:65` | "Full vocabulary in" |
| `research/deepening/dependencies.md` | `actions/deepening.md:37` | "Classify each candidate's dependencies per" |
| `research/deepening/html-report.md` | `actions/deepening.md:63` | "Full scaffold and diagram patterns in" |
| `research/deepening/interface-design.md` | `actions/deepening.md:108` | Design-It-Twice branch |

`scan-briefing.md` is the load-bearing one: `actions/deepening.md:26` says using it is what keeps
scan quality from varying run to run, and it is two levels from the hub.

Remediation: add a hub-level index in `plugins/architecture/skills/improve/SKILL.md`, next to the
existing `actions/deepening.md` row at line 35, so each research file is one level deep. Keep the
call sites in `actions/deepening.md`.

```markdown
## Reference index. Load on demand

- [`research/deepening/scan-briefing.md`](research/deepening/scan-briefing.md). Read before
  dispatching the first scan subagent: the canonical briefing that keeps scan quality and
  confidence calibration constant across runs.
- [`research/deepening/vocabulary.md`](research/deepening/vocabulary.md). Read when applying the
  deletion test or naming a candidate: the architecture vocabulary.
- [`research/deepening/dependencies.md`](research/deepening/dependencies.md). Read when
  classifying a candidate's dependencies, since the category picks the testing strategy.
- [`research/deepening/html-report.md`](research/deepening/html-report.md). Read before writing
  the report: the scaffold and the diagram patterns.
- [`research/deepening/interface-design.md`](research/deepening/interface-design.md). Read when
  the run enters the Design-It-Twice branch.
```

### Not a finding

`plugins/event-storming/skills/methodology/SKILL.md:147` (`## Reference Documents`) and the
matching section in `skills/simulation/SKILL.md:140` carry a condition on every row, for example
`SKILL.md:151`:

```text
**For running a Big Picture workshop**: `@./reference/big-picture-workshop.md`
```

That is the pointer shape the rubric asks for. The `detect.sh` orphan report against these files
is a false positive of the script bug recorded in `A-doc-quality.md`.

### `missing-toc`, 100 to 300 lines (Tier 3, awareness only)

28 files. No treatment.

## Cross-lane observations

- `plugins/overengineering/context/scrutiny-method.md` and
  `plugins/overengineering/skills/audit/SKILL.md` both describe the scrutiny ladder. L3.
- `plugins/event-storming/skills/simulation/reference/agentic-simulation.md` at 1,023 lines is the
  largest single spoke in this group; whether it earns its existence against the methodology
  skill's own references is an L1 question.
