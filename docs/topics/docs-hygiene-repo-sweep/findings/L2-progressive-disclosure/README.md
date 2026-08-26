# L2 progressive disclosure: corpus roll-up

Wave 1 audit of all 1,302 in-scope files against
`/docs-hygiene:audit-progressive-disclosure`. Read-only: no source file was created, split,
edited, or moved. Every entry below carries a remediation spec in its group file, and every split
spec names the new spoke path, the exact line range that moves, and the replacement pointer text,
because `L3-ssot` and `L4-encapsulation` run after this lane in wave 3 and will cite the
post-split layout.

## What fired, and what did not

The corpus is already good at hub-and-spoke: 243 skills, 503 reachable spokes, and after
correcting for a detector bug (below) only **4 unreachable spokes** out of 507. The two real
problems are at the ends of the economy.

**At `T2`**, a cluster of skill bodies sits at the 500-line ceiling with on-demand reference
material inlined, and three of them have **no spokes at all**. A `SKILL.md` pays its full cost for
the rest of a session once triggered, so this is where the corpus's disclosure debt actually costs
something.

**At `T3`**, 120 reference files above 300 lines have no table of contents. Size costs nothing at
this tier, but every one of these is entered by a reader looking for one named thing, which is
exactly the access pattern a TOC or grep recipe serves and a full read does not.

Nothing fired on `T1`. Three files, 466 bytes, two of them empty or a one-line import. Two
awareness notes are recorded in `M-repo-root.md` so a later reader can see they were considered.

## Counts by shape and tier

Counting convention: one finding per presented entry, except tables where each row names its own
path (`missing-toc` and `blind-pointer` tables), which count per path. The 303 corpus-wide files
in the 100-to-300-line TOC awareness band count as **one Tier 3 entry per group**, not 303
findings, since the two official sources disagree at that length and the entries carry no
treatment.

| Shape | Lane | T1 | T2 | T3 | Total |
|---|---|---:|---:|---:|---:|
| `oversize` | split | 0 | 27 | 0 | 27 |
| `mixed-concerns` | split | 0 | 3 | 0 | 3 |
| `tier-mismatch` | split | 0 | 1 | 2 | 3 |
| `blind-pointer` | structure | 0 | 21 | 1 | 22 |
| `orphan-spoke` | structure | 0 | 3 | 1 | 4 |
| `deep-nesting` | structure | 0 | 4 | 2 | 6 |
| `missing-toc` | structure | 120 | 2 | 13 | 135 |
| **Total** | | **120** | **61** | **19** | **200** |

Split lane: 33. Structure lane: 167.

## Counts by group

| Group | Files | T2 files | T1 | T2 | T3 | Total | Heaviest shape |
|---|---:|---:|---:|---:|---:|---:|---|
| `A-doc-quality` | 78 | 15 | 1 | 8 | 1 | 10 | `blind-pointer` |
| `B-cc-config-ops` | 130 | 29 | 9 | 9 | 2 | 20 | `missing-toc` |
| `C-vcs-repo` | 93 | 17 | 11 | 7 | 1 | 19 | `missing-toc` |
| `D-work-planning` | 109 | 28 | 4 | 12 | 1 | 17 | `oversize` |
| `E-session-behavior` | 145 | 38 | 9 | 4 | 1 | 14 | `missing-toc` |
| `F-quality-verify` | 121 | 31 | 5 | 3 | 1 | 9 | `missing-toc` |
| `G-code-design` | 94 | 17 | 7 | 2 | 1 | 10 | `missing-toc` |
| `H-knowledge-research` | 133 | 32 | 5 | 9 | 2 | 16 | `oversize` |
| `I-songwriting` | 106 | 12 | 40 | 2 | 2 | 44 | `missing-toc` |
| `J-toolchain-platform` | 137 | 31 | 1 | 2 | 1 | 4 | `oversize` |
| `K-repo-docs` | 89 | 0 | 15 | 2 | 1 | 18 | `missing-toc` |
| `L-docs-topics` | 57 | 0 | 12 | 0 | 2 | 14 | `missing-toc` |
| `M-repo-root` | 10 | 0 | 1 | 1 | 3 | 5 | `mixed-concerns` |

## Ranked split candidates

Ranked by extractable mass at the tier that pays for it, not by raw size. `Extract` is the line
count the group file's spec moves out of the body.

| # | Path | Tier | Size | Spokes | Extract | Result | Shape |
|---:|---|---|---|---:|---:|---|---|
| 1 | `plugins/discipline/skills/sweep-all/SKILL.md` | T2 | 469 L / 4,357 w | 0 | 300 | 187 L | `oversize` + `mixed-concerns` |
| 2 | `plugins/work-items/skills/setup/SKILL.md` | T2 | 498 L / 6,153 w | 4 | 265 | 253 L | `oversize` + `mixed-concerns` |
| 3 | `plugins/session-flow/skills/find-handoff/SKILL.md` | T2 | 486 L / 5,813 w | 0 | 237 | 269 L | `oversize` |
| 4 | `plugins/autonomy/skills/setup/SKILL.md` | T2 | 494 L / 4,527 w | 10 | 224 | 292 L | `oversize` + `mixed-concerns` |
| 5 | `plugins/context-guard/skills/setup/SKILL.md` | T2 | 462 L / 4,715 w | 0 | 180 | 292 L | `oversize` + `tier-mismatch` |
| 6 | `plugins/plugin-quality/skills/audit/SKILL.md` | T2 | 499 L / 5,579 w | 6 | 178 | 332 L | `oversize` + `tier-mismatch` |
| 7 | `plugins/claude-config/skills/audit-instructions/SKILL.md` | T2 | 487 L / 5,154 w | 4 | 158 | 337 L | `oversize` |
| 8 | `plugins/overengineering/skills/delta/SKILL.md` | T2 | 480 L / 5,796 w | 1 | 149 | 353 L | `oversize` + `tier-mismatch` |
| 9 | `plugins/disk-hygiene/skills/clean/SKILL.md` | T2 | 499 L / 4,848 w | 1 | 133 | 378 L | `mixed-concerns` + `oversize` |
| 10 | `plugins/source-control/skills/babysit-loop/SKILL.md` | T2 | 499 L / 5,713 w | 4 | 126 | 385 L | `oversize` |

Next ten, same treatment shape, specs in the group files:

| # | Path | Tier | Size | Extract |
|---:|---|---|---|---:|
| 11 | `plugins/work-items/skills/attend-queue/SKILL.md` | T2 | 338 L / 3,400 w | 115 |
| 12 | `plugins/work-items/skills/decompose/SKILL.md` | T2 | 317 L / 3,580 w | 118 |
| 13 | `plugins/knowledge/skills/docpage-digest/SKILL.md` | T2 | 321 L / 3,312 w | 89 |
| 14 | `plugins/work-items/skills/work-loop/SKILL.md` | T2 | 477 L / 4,816 w | 87 |
| 15 | `plugins/claude-config/skills/audit-pass/SKILL.md` | T2 | 495 L / 5,476 w | 77 |
| 16 | `plugins/planning/skills/plan/SKILL.md` | T2 | 363 L / 6,338 w | 75 |
| 17 | `plugins/work-items/skills/work/SKILL.md` | T2 | 264 L / 5,058 w | 122 |
| 18 | `plugins/discovery/agents/intent-tracer.md` | T2 | 341 L / 3,728 w | 71 |
| 19 | `plugins/education/skills/teach/SKILL.md` | T2 | 265 L / 4,538 w | 63 |
| 20 | `plugins/mutation-testing/skills/audit/SKILL.md` | T2 | 406 L / 4,360 w | 115 |

Remaining `T2` splits: `plugins/discovery/skills/research/SKILL.md` (234 L / 5,058 w, extract 49),
`plugins/discovery/skills/explore/SKILL.md` (224 L / 4,045 w, extract 52),
`plugins/planning/skills/interview/SKILL.md` (302 L / 6,346 w, extract 37 as a `tier-mismatch`
collapse into an existing spoke), `plugins/work-items/skills/triage/SKILL.md` (198 L / 4,070 w,
extract 56), `plugins/source-control/skills/babysit-prs/SKILL.md` (429 L / 4,932 w, extract 83),
`plugins/source-control/skills/pull-request/SKILL.md` (290 L / 4,764 w, extract 43),
`plugins/source-control/skills/setup/SKILL.md` (343 L / 3,384 w, extract 133),
`plugins/source-control/skills/worktree/SKILL.md` (205 L / 4,169 w, extract 25).

Two `T3` splits, driven by concern mixing rather than cost:
`prompts/loops/loop-lane-prompts.md` (1,961 L, extract 775, `mixed-concerns`) and
`docs/MIGRATION-PLAYBOOK.md` (1,738 L, extract 266 into six new ADRs, `mixed-concerns` +
`tier-mismatch`).

## Structural defects

166 findings across four shapes.

### `orphan-spoke`: 4

Four unreachable spokes in a tree of 507. Every one was verified by an independent repo-wide
reachability pass and by a targeted grep before being reported.

| Path | Tier | Lines | Verdict | Group |
|---|---|---:|---|---|
| `plugins/ai-briefing/skills/generate/context/execution-flow.md` | T3 | 105 | Tier 2. Genuinely dead: the string appears nowhere in `plugins/**` outside itself. Delete, or add a hub pointer. Overlaps L1. | `H` |
| `plugins/implementation/skills/implement/context/gotchas.md` | T3 | 41 | Tier 2. Dead within its skill: its three siblings are cited from the mode table at `SKILL.md:43-45`, it is not, and `SKILL.md:210` carries a `## Gotchas` heading inline instead. Add the pointer, move the inline entries into the file. | `D` |
| `plugins/songwriting/skills/suno/reference/suno-drift-audit-ledger.md` | T3 | 34 | Tier 2. Maintenance ledger, unreferenced. Add a pointer under a new maintenance section, or move to plugin scope. | `I` |
| `plugins/knowledge/skills/video-digest/extraction/liveness/LIVENESS.md` | T3 | 74 | Tier 3. Co-located script README beside `run-source-liveness.js`, not a disclosure spoke. No treatment. | `H` |

The first two are the same two files a prior measurement in this repo named by hand at
`docs/topics/context-engineering-claude-5/design/article-sections.md:25`. Two independent passes
agree on them.

### `deep-nesting`: 6

| Path | Tier | Chain | Group |
|---|---|---|---|
| `plugins/claude-config/skills/audit-pass/reference/terms.md` and `reference/finding-identity.md` | 2 | `SKILL.md:19` -> `reference/run-contract.md:9` -> leaf. Every other leaf opens by assuming `terms.md`, and it is the file furthest from the hub. | `B` |
| `plugins/architecture/skills/improve/research/deepening/*.md` (5 files) | 2 | `SKILL.md:35` -> `actions/deepening.md:26` -> `research/deepening/scan-briefing.md`. The citing line calls the target load-bearing for scan quality. | `G` |
| `plugins/session-flow/skills/retro/reference/ecosystem-improvement-catalog.md` | 2 | `SKILL.md` -> `context/session.md:184` ("Load the catalog") -> the catalog. | `E` |
| `plugins/knowledge/skills/course-digest/reference/screenshot-strategy.md` | 2 | `SKILL.md` -> `context/workflow.md:46` -> the strategy. | `H` |
| `plugins/claude-ops/skills/known-issues/context/issue-templates.md`, `context/output-templates.md` | 3 | Explicitly conditional offline snapshots. Alternates, not required reading. No treatment. | `B` |
| `plugins/songwriting/context/pat-pattison/research/book-references.md` | 3 | Shared bibliography cited by its siblings. Legitimate cross-reference. No treatment. | `I` |

### `blind-pointer`: 22

Almost all of one shape: a trailing index section that names what each spoke holds and never says
when to open it. The repo already contains three correct versions of this section, so the
remediation is a rename plus a when-clause per row, not a new convention:

- `plugins/plugin-quality/skills/audit/SKILL.md:485`, `## Reference index. Load on demand` with a
  literal `Load when` table column. The best example in the corpus.
- `plugins/source-control/skills/commit/SKILL.md:377`, same heading.
- `plugins/claude-ops/skills/observability/SKILL.md:36`, `## Context ladder (read on demand)`.

| Site | Heading | Rows | Group |
|---|---|---:|---|
| `plugins/docs-hygiene/skills/{audit-derivability,audit-noise,audit-progressive-disclosure,compress,extract-ssot}/SKILL.md` | inline shared-fallback sentence | 5 | `A` |
| `plugins/docs-hygiene/skills/{audit-encapsulation,compress,extract-ssot}/SKILL.md` | `## Cross-references` | 3 | `A` |
| `plugins/claude-ops/skills/{changelog,lanes,morning-brief,observability,plugins}/SKILL.md` | `## Cross-references` | 5 | `B` |
| `plugins/bugs/skills/{scan,write}/SKILL.md` | `## Cross-references` | 2 | `F` |
| `plugins/ai-briefing/skills/generate/SKILL.md:140` | `## References` | 1 | `H` |
| `plugins/discovery/skills/research-deep/SKILL.md:120` | `## See also` | 1 | `H` |
| `plugins/source-control/skills/babysit-prs/SKILL.md:409` | `## References` | 1 | `C` |
| `plugins/kindle-dedrm/skills/manage/SKILL.md:154` | `## Cross-references` | 1 | `J` |
| `plugins/planning/skills/interview/SKILL.md:277` | spoke listed under `## What this skill does NOT do` | 1 | `D` |
| `plugins/work-items/skills/onboard-adapter/SKILL.md:203` | `## Related` | 1 | `D` |
| `docs/topics/ai-adoption-ladder/design/design-threads.md` | nine bare-name citations, Tier 3 awareness | 1 | `L` |

### `missing-toc`: 135

120 Tier 1 (above 300 lines, both official sources agree a TOC is expected), 2 Tier 2 (a
directory with no index at all), 13 Tier 3 (one awareness entry per group for the 303 files in the
contested 100-to-300 band).

Tier 1 concentration:

| Group | Files | Largest |
|---|---:|---|
| `I-songwriting` | 40 | `context/pat-pattison/research/meter.md`, 1,922 L |
| `K-repo-docs` | 15 | `docs/MIGRATION-PLAYBOOK.md`, 1,738 L |
| `L-docs-topics` | 12 | `docs/topics/context-engineering-claude-5/PLAN.md`, 1,167 L |
| `C-vcs-repo` | 11 | `plugins/source-control/skills/babysit-prs/reference/orchestration.md`, 962 L |
| `B-cc-config-ops` | 9 | `plugins/claude-config/skills/audit-instructions/reference/criteria.md`, 1,742 L |
| `E-session-behavior` | 9 | `plugins/session-flow/reference/save-point.md`, 566 L |
| `G-code-design` | 7 | `plugins/event-storming/skills/simulation/reference/agentic-simulation.md`, 1,023 L |
| `F-quality-verify` | 5 | `plugins/review/skills/quality-gate/context/close-out.md`, 415 L |
| `H-knowledge-research` | 5 | `plugins/knowledge/skills/docpage-digest/context/anthropic-docs-profile.md`, 420 L |
| `D-work-planning` | 4 | `plugins/work-items/tools/work-item-tracker/CONTRACT.md`, 769 L |
| `A-doc-quality` | 1 | `plugins/ai-slop/skills/audit/reference/catalog.md`, 901 L |
| `J-toolchain-platform` | 1 | `plugins/machine-health/skills/audit/references/windows/check-catalog.md`, 352 L |
| `M-repo-root` | 1 | `prompts/loops/loop-lane-prompts.md`, 1,961 L |

The repo's own TOC pattern is
`plugins/docs-hygiene/skills/audit-progressive-disclosure/context/tier-model.md:3-9`: a
`## Contents` heading under the H1 with one anchor link per H2. Every remediation above targets
that shape. This is the one finding class in the sweep that is safely scriptable from each file's
own headings; treat it as one mechanical pass, not 120 edits.

The two Tier 2 index gaps are `plugins/songwriting/context/pat-pattison/research/` (51 files, no
`README.md`) and `docs/` (12 top-level files plus 6 subdirectories, no `README.md`). Both are new
index files, not splits, so they move no path and create no wave-3 ordering dependency.

## Wave 3 ordering notes for the orchestrator

This lane runs at step 2, after deletions and before SSOT and encapsulation. Three things follow.

1. **`plugins/ai-briefing/skills/generate/context/execution-flow.md` is contested between L1 and
   L2.** It is an orphan by this lane's rubric and a delete candidate by L1's. If L1 deletes it at
   step 1, this lane's finding is moot and should be struck, not applied.
2. **Two splits create files that L3 will immediately want to dedup.**
   `plugins/work-items/skills/attend-queue/reference/telemetry-upsert.md` duplicates
   `plugins/work-items/skills/work-loop/reference/telemetry-upsert.md`, and
   `plugins/discovery/reference/tool-honesty.md` is extracted from one of three agents that carry
   the same rule. Both splits are deliberately the mass-reduction step only; L3 owns the collapse.
3. **`docs/MIGRATION-PLAYBOOK.md` is the only split with heavy inbound citations.** It is cited
   from many plugin CHANGELOGs and from `docs/PLUGIN-PHILOSOPHY.md`. No citation found in this
   pass targets a moved section by anchor, but the applying agent must re-check before cutting,
   and L4 owns any rewrite that falls out.

Three splits do **not** apply and are called out in their group files so a later reader does not
undo the reasoning: the inlined rate-limit-guard floors in
`plugins/source-control/skills/babysit-loop/SKILL.md:402`,
`plugins/work-items/skills/work-loop/SKILL.md:159`, and
`plugins/work-items/skills/attend-queue/SKILL.md:278` are required byte-identical in the body by
the loop-lane convention's inline-floor rule.

## Reading these files

Verbatim quotes of source text appear in fenced `text` blocks, not blockquotes. That is
deliberate: the repo's `markdown-format` hook normalizes spacing around inline code spans, which
silently alters a quoted line that carries its own backticks, and a verbatim quote that no longer
matches its source cannot be applied or verified. Every quoted line in this findings set is
byte-exact against the cited `path:line`.

Proposed replacement text also appears in fenced blocks. Where a replacement reproduces an
existing heading (for example `## Phase 3 — Execute` in `F-quality-verify.md`), the heading is
kept byte-identical including its em dash, so the edit applies cleanly. The house style rule
against em dashes applies to this findings set's own prose, which carries none.

## Method, and one detector defect

Facts came from one `detect.sh` pass over `plugins/`, `docs/`, `.claude/`, `.github/`, `prompts/`,
and the root files (1,243 files; the 60 manifest files under `evals/fixtures/` are a skip surface
per the rubric and were not scanned). Judgment was applied on top of those facts, and every
`orphan-spoke` claim was verified by an independent repo-wide reachability pass before being
reported.

**That verification changed the result, and the reason is a bug worth reporting.**
`plugins/docs-hygiene/skills/audit-progressive-disclosure/scripts/detect.sh` reported **132 orphan
spokes**. The real number is **4**.

`detect.sh:169` defines `md_links()` as a pipeline beginning with `grep`. Under the script's
`set -euo pipefail`, that pipeline exits 1 for any file with zero markdown links. `ref_candidates()`
at line 259 calls `md_links` first inside a `{ ...; }` group whose second command is the
backtick-mention grep, so `set -e` aborts the group before the backtick branch ever runs. Result:
**every hub whose `SKILL.md` cites its spokes only in backticks reports all of its spokes as
orphans.** The script also cannot resolve `${CLAUDE_PLUGIN_ROOT}`-rooted paths, `@./` import
forms, or directory-level pointers, which are this repo's three dominant citation conventions.

The independently-derived count agrees with a prior measurement recorded in this repo at
`docs/topics/context-engineering-claude-5/design/article-sections.md:25`, which named the same two
`plugins/**` files by hand and stated the general lesson this pass re-learned: "Anyone reporting a
count without naming the files is reporting their resolver's limits." Every orphan and
deep-nesting claim in this findings set names its files.

The bug belongs to whoever owns that script, not to this sweep. It is recorded in
`A-doc-quality.md` under cross-lane observations.

## Group files

- [`A-doc-quality.md`](A-doc-quality.md)
- [`B-cc-config-ops.md`](B-cc-config-ops.md)
- [`C-vcs-repo.md`](C-vcs-repo.md)
- [`D-work-planning.md`](D-work-planning.md)
- [`E-session-behavior.md`](E-session-behavior.md)
- [`F-quality-verify.md`](F-quality-verify.md)
- [`G-code-design.md`](G-code-design.md)
- [`H-knowledge-research.md`](H-knowledge-research.md)
- [`I-songwriting.md`](I-songwriting.md)
- [`J-toolchain-platform.md`](J-toolchain-platform.md)
- [`K-repo-docs.md`](K-repo-docs.md)
- [`L-docs-topics.md`](L-docs-topics.md)
- [`M-repo-root.md`](M-repo-root.md)
