# docs-hygiene-sweep-unapplied-remediations

The remediation set the repo-wide `docs-hygiene` sweep produced and had not applied when this record
was written. Every entry below is located by `path:line`, every line was verified against the
working tree on 2026-08-26, and the small high-value sets carry their verbatim source text and exact
replacement.

This document exists so the work is resumable without re-auditing. The audit itself was the
expensive half: 1302 files, eight lanes, corpus-wide mechanical detectors substituting for a
fan-out that was not available, and a rejection rate high enough that re-deriving these findings
means paying for thousands of rejections again. See
[`docs-hygiene-sweep-yield-measurement.md`](docs-hygiene-sweep-yield-measurement.md) for those
denominators and for why re-running the prose lanes is not worth it.

## Decay rule

**This is a point-in-time record, stamped 2026-08-26, written while the sweep's own apply pass was
still running in another session.** Several in-file prose findings and several splits landed between
the first and last verification pass of this document, and are marked below as they stood at the
stamp.

So the status column is the weakest thing here and the verbatim text is the strongest. **The check
is the text, never the status and never the line number.** If a finding's quoted source text is
still present at or near the cited path, the finding is open. If the replacement text is present
instead, it is done. A finding whose quote matches nothing in the file has been applied, superseded,
or moved by a split, and needs re-resolution rather than re-application.

The inventory itself does not decay: what each lane found, what it declined, and what it could not
reach are the parts that cannot be re-derived without re-running the audit.

## Contents

- [Status at the stamp](#status-at-the-stamp)
- [How to apply anything in this document](#how-to-apply-anything-in-this-document)
- [Standing hazards, all lanes](#standing-hazards-all-lanes)
- [L2 splits: 21 files](#l2-splits-21-files)
- [L2 structure: 167 findings](#l2-structure-167-findings)
- [L3 deduplication: 13 clusters remediated, 13 refused](#l3-deduplication-13-clusters-remediated-13-refused)
- [L4 encapsulation: 34 violations](#l4-encapsulation-34-violations)
- [L5 noise: 10 findings](#l5-noise-10-findings)
- [L6 compression: 1 finding](#l6-compression-1-finding)
- [L7 write-for-agents: 13 findings](#l7-write-for-agents-13-findings)
- [L8 write-for-humans: 57 findings and 6 reclassifications](#l8-write-for-humans-57-findings-and-6-reclassifications)
- [Recall limits each lane declared](#recall-limits-each-lane-declared)

## Status at the stamp

Applied in the sweep's own change set before this record was written, and therefore **not** listed
below:

- Both `L1` derivability outcomes. `plugins/repo-hygiene/skills/clean/reference/ecosystems.md` and
  `plugins/ai-briefing/skills/generate/context/execution-flow.md` are deleted, the second only after
  four behavioral rules were salvaged into its `SKILL.md`, and
  `plugins/claude-ops/skills/known-issues/context/issue-templates.md` is converted to a pointer.
- Nine of the 30 `L2` split specs.
- `L6`'s finding C1, fixed at `scripts/sync-plugin-options-docs.py` and regenerated into 34 plugin
  READMEs.
- Four detector defects, recorded in `plugins/docs-hygiene/CHANGELOG.md` 0.21.12 through 0.21.15.
- The two `E1` doctrine edits, now recorded as
  [ADR 0018](../adr/0018-treat-the-plugin-as-the-encapsulation-boundary-for-skill-citation.md), and
  the `E4` narrowing of `write-for-agents`'s own disclaimer.

Everything else the sweep produced is below.

**Landing during the writing of this record**, measured at the stamp rather than assumed. The apply
pass was consuming the in-file prose lanes and part of the split lane while this document was being
written, so these counts are a floor on what has since shipped, not a ceiling:

| Lane | At the stamp |
|---|---|
| L2 splits | 8 of the 21 below had landed: `work-items` `setup`, `attend-queue`, `decompose`, `work-loop`, `work`, `triage`, plus `planning` `plan` and `interview` |
| L4 encapsulation | 0 of 34. Sampled 16 of the 34 citations at the stamp and all 16 were still open |
| L5 noise | 7 of 10 had landed. Still open: the two `babysit-prs` `negation` findings and the `babysit-prs` `plan-reference` finding |
| L6 compression | 0 of 1 |
| L7 write-for-agents | 9 of 13 had landed. Still open at the stamp: `H-1` and the `write-for-agents` doctrine edit. The `I-1` batch is settled and closed as of 2026-08-26: declined, with its count corrected from 31 across 16 files to 104 across 26 |
| L8 write-for-humans | Partly landed; not individually re-measured, because the class fixes (`Am1`, `M3`) are mechanical enough that a match against the quoted shape settles each site faster than a stale status column would |
| L2 structure, L3 | Not observed to move |

## How to apply anything in this document

1. **Match the quoted text, not the line number.** Line numbers here were verified on 2026-08-26 and
   every one resolved at the time, but the apply pass and any split from the L2 section move lines
   in the same file.
2. **Re-resolve after each dependency step.** The sweep's own ordering holds: deletions, then
   splits, then deduplication, then citation rewrites, then one merged in-file prose pass. A
   citation rewritten before a split targets a path about to move.
3. **One editor per file.** The L5, L6, L7 and L8 findings are all in-file prose edits; merge every
   finding for one file into one edit rather than making four passes at it.
4. **`compress` cannot gate itself.** `docs-hygiene:compress` requires a semantic-diff subagent and
   requires that the compressing context not be the verifying context. Any compression edit needs
   that gate run from a context that can spawn one.

## Standing hazards, all lanes

- **Generated blocks.** Roughly 70 lines in each of 34 plugin READMEs sit between
  `<!-- BEGIN GENERATED: plugin options ... -->` and its `END` marker, emitted by
  `scripts/sync-plugin-options-docs.py` and checked in CI by `plugin-options-docs-gate`. **Reject
  any edit whose line falls inside such a block.** A hand edit there fails CI and reverts on the
  next sync. Route it to the generator.
- **Fixtures are not prose.** 62 rows under `evals/fixtures/` and `scripts/fixtures/` are test data,
  several deliberately defective specimens that anchor a passing eval. Editing one breaks the test
  it exists for. Excluding them belongs in the manifest generator, not in each lane.
- **Mandated duplication.** Plugin contracts are carried inline at every adopting site on purpose,
  because plugins ship without the marketplace repository
  (`docs/conventions/untrusted-content/README.md:34`). Repetition there is portability.
- **Quoted material.** Several corpus files quote external authors verbatim. Compressing or
  de-noising a quotation misattributes it.
- **Inline-floor rules.** The rate-limit-guard floors at
  `plugins/source-control/skills/babysit-loop/SKILL.md`,
  `plugins/work-items/skills/work-loop/SKILL.md` and
  `plugins/work-items/skills/attend-queue/SKILL.md` are required byte-identical in the body by the
  loop-lane convention. Do not split or dedup them.

## L2 splits: 21 files

Every spec below names the new spoke path and the line range that moves. `Extract` is the line count
that leaves the body. `Size` is what the audit measured; re-measured at the stamp, 13 of the 21 files
were byte-for-byte at that size and 8 had already been split by the apply pass (entries 2, 7, 8, 10,
11, 12, 18, 19). The line ranges below are the audit's, so on an already-split file read the range as
a description of what moved rather than as coordinates.

| # | Hub | Tier | Size at audit | Extract | New spoke, and the range that moves |
|---:|---|---|---|---:|---|
| 1 | `plugins/discipline/skills/sweep-all/SKILL.md` | T2 | 469 L / 4,357 w | 300 | `reference/inheritance-preflight.md` (68 to 212); `reference/batched-pass.md` (214 to 366) |
| 2 | `plugins/work-items/skills/setup/SKILL.md` | T2 | 498 L / 6,153 w | 265 | `reference/autonomous-apply.md` (260 to 414, promoted to H1) |
| 3 | `plugins/session-flow/skills/find-handoff/SKILL.md` | T2 | 486 L / 5,813 w | 237 | `reference/rung-1-known-location.md` (83 to 184); `reference/rung-3-marker-detection.md` (193 to 318) |
| 4 | `plugins/autonomy/skills/setup/SKILL.md` | T2 | 494 L / 4,527 w | 224 | `context/guardrail-slice.md` (209 to 303); `context/routine-slice.md` (305 to 431) |
| 5 | `plugins/plugin-quality/skills/audit/SKILL.md` | T2 | 499 L / 5,579 w | 178 | `references/evidence-packet.md` (121 to 298, note the plural directory this plugin uses) |
| 6 | `plugins/overengineering/skills/delta/SKILL.md` | T2 | 480 L / 5,796 w | 149 | `context/baseline-model.md` (94 to 170); `context/run-states.md` (238 to 307) |
| 7 | `plugins/work-items/skills/attend-queue/SKILL.md` | T2 | 338 L / 3,400 w | 115 | `reference/telemetry-upsert.md` (163 to 277). Do **not** merge with the work-loop copy; that is L3's call. Do **not** split lines 278 to 319, the inlined rate-limit floor |
| 8 | `plugins/work-items/skills/decompose/SKILL.md` | T2 | 317 L / 3,580 w | 118 | Opt-in container lifecycle (194 to 260) and re-decompose (265 to 317); neither co-executes with the default first pass |
| 9 | `plugins/knowledge/skills/docpage-digest/SKILL.md` | T2 | 321 L / 3,312 w | 89 | `context/dual-verification.md` (163 to 251) |
| 10 | `plugins/work-items/skills/work-loop/SKILL.md` | T2 | 477 L / 4,816 w | 87 | `reference/admission-gate.md` (295 to 381) |
| 11 | `plugins/planning/skills/plan/SKILL.md` | T2 | 363 L / 6,338 w | 75 | `templates/plan-md-anatomy.md` (270 to 343). Keep separate from `context/plan-template.md`: that is the plan body template, this is the PLAN.md file skeleton |
| 12 | `plugins/work-items/skills/work/SKILL.md` | T2 | 264 L / 5,058 w | 122 | `context/claim-and-execute.md` (215 to 261); `context/selection.md` (105 to 179) |
| 13 | `plugins/discovery/agents/intent-tracer.md` | T2 | 341 L / 3,728 w | 71 | `plugins/discovery/reference/tool-honesty.md` (93 to 163). L3 owns the collapse of the three agents carrying the same rule |
| 14 | `plugins/education/skills/teach/SKILL.md` | T2 | 265 L / 4,538 w | 63 | `context/pedagogy.md` (134 to 196, H3s raised to H2) |
| 15 | `plugins/mutation-testing/skills/audit/SKILL.md` | T2 | 406 L / 4,360 w | 115 | `templates/report.md` (251 to 293); `context/execute.md` (123 to 194) |
| 16 | `plugins/discovery/skills/research/SKILL.md` | T2 | 234 L / 5,058 w | 49 | `context/routing.md` (23 to 71). Keep separate from `context/dispatch.md`, which owns the parent-side contract |
| 17 | `plugins/discovery/skills/explore/SKILL.md` | T2 | 224 L / 4,045 w | 52 | `context/routing.md` (21 to 72) |
| 18 | `plugins/planning/skills/interview/SKILL.md` | T2 | 302 L / 6,346 w | 37 | `tier-mismatch`, not a new spoke: lines 233 to 274 collapse into the existing `context/session-config.md`, which already declares itself the reference layer for that exact section |
| 19 | `plugins/work-items/skills/triage/SKILL.md` | T2 | 198 L / 4,070 w | 56 | `context/apply-outcome.md` |
| 20 | `prompts/loops/loop-lane-prompts.md` | T3 | 1,961 L | 775 | `prompts/loops/loop-lane-profile-claude-code-plugins.md` (1,187 to 1,961). The file declares itself repository-agnostic and 40% of it is one repository's filled instance |
| 21 | `docs/MIGRATION-PLAYBOOK.md` | T3 | 1,738 L | 266 | Six dated decision records (1,473 to 1,738) move to `docs/adr/`. **Renumber:** the spec was written for 0018 through 0023, and 0018 is now taken, so they land at 0019 through 0024 |

`plugins/implementation/skills/implement-dispatch/SKILL.md` was measured and is **not** a finding:
118 lines but 3,420 words, roughly 29 words per line. It is recorded because a future addition
crosses the ceiling without the line count moving.

The `MIGRATION-PLAYBOOK.md` split is the only one with heavy inbound citation. It is cited from many
plugin changelogs and from `docs/PLUGIN-PHILOSOPHY.md`. No citation found in the audit targets a
moved section by anchor, but re-check anchors before cutting.

## L2 structure: 167 findings

| Shape | Count | Applied |
|---|---:|---|
| `missing-toc` | 135 | none |
| `blind-pointer` | 22 | none |
| `deep-nesting` | 6 | none |
| `orphan-spoke` | 4 | 1 resolved by deletion, 1 is a no-treatment awareness row |

### `missing-toc`, 135

**This one is re-derivable and should be re-derived rather than trusted.** It is a mechanical
predicate over each file's own headings, it is the one finding class in the sweep that is safely
scriptable, and it should be treated as one pass rather than 135 edits.

The predicate: a file above 300 lines with no `## Contents` section, excluding changelogs, vendor
trees and fixtures. Re-running it on 2026-08-26 over the tracked corpus outside `docs/topics/`
returns **134** files. The audit's own count was 120 at a different exclusion boundary and before
nine splits landed, so use the live number.

The target shape is the repo's own, at
`plugins/docs-hygiene/skills/audit-progressive-disclosure/context/tier-model.md:3-9`: a
`## Contents` heading under the H1 with one anchor link per H2.

Concentration by group, as measured, for scoping:

| Group | Files | Largest |
|---|---:|---|
| `I-songwriting` | 40 | `plugins/songwriting/context/pat-pattison/research/meter.md`, 1,922 L |
| `K-repo-docs` | 15 | `docs/MIGRATION-PLAYBOOK.md`, 1,738 L |
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

Two directory-level index gaps, which are new files rather than splits and create no ordering
dependency: `plugins/songwriting/context/pat-pattison/research/` (51 files, no `README.md`) and
`docs/` (12 top-level files plus 6 subdirectories, no `README.md`).

The 303 files in the 100-to-300-line band are **not** findings. The two official sources disagree at
that length, and the audit carried them as one awareness entry per group with no treatment.

### `blind-pointer`, 22

Almost all one shape: a trailing index section that names what each spoke holds and never says when
to open it. The remediation is a rename plus a when-clause per row, not a new convention, because
the repository already contains three correct versions of the section:

- `plugins/plugin-quality/skills/audit/SKILL.md:485`, `## Reference index. Load on demand`, with a
  literal `Load when` table column. The best example in the corpus.
- `plugins/source-control/skills/commit/SKILL.md:377`, same heading.
- `plugins/claude-ops/skills/observability/SKILL.md:36`, `## Context ladder (read on demand)`.

| Site | Heading | Rows |
|---|---|---:|
| `plugins/docs-hygiene/skills/{audit-derivability,audit-noise,audit-progressive-disclosure,compress,extract-ssot}/SKILL.md` | inline shared-fallback sentence | 5 |
| `plugins/docs-hygiene/skills/{audit-encapsulation,compress,extract-ssot}/SKILL.md` | `## Cross-references` | 3 |
| `plugins/claude-ops/skills/{changelog,lanes,morning-brief,observability,plugins}/SKILL.md` | `## Cross-references` | 5 |
| `plugins/bugs/skills/{scan,write}/SKILL.md` | `## Cross-references` | 2 |
| `plugins/ai-briefing/skills/generate/SKILL.md:140` | `## References` | 1 |
| `plugins/discovery/skills/research-deep/SKILL.md:120` | `## See also` | 1 |
| `plugins/source-control/skills/babysit-prs/SKILL.md:409` | `## References` | 1 |
| `plugins/kindle-dedrm/skills/manage/SKILL.md:154` | `## Cross-references` | 1 |
| `plugins/planning/skills/interview/SKILL.md` | spoke listed under `## What this skill does NOT do`. **Open, and deliberately left standing. See below** | 1 |
| `plugins/work-items/skills/onboard-adapter/SKILL.md:203` | `## Related` | 1 |
| `docs/topics/ai-adoption-ladder/design/design-threads.md` | nine bare-name citations, awareness only | 1 |

Three of L7's P3 pointer findings overlap this shape. Where both fire on one line, take the
blind-pointer rewrite, which is fuller, and drop the P3 fix rather than applying both.

**Correction, 2026-08-26.** That cross-lane note has no referent. It and the L7 note that
`B-1` through `B-4` "also fail L2's blind-pointer shape" both point at
`plugins/claude-ops/skills/audit-install-state/SKILL.md`, which the table above never listed: its
eleven rows sum to exactly 22 without it. The two notes also disagree with each other on the count,
three against four. Independently, all four `B-1` through `B-4` replacements are already present in
that file, so those findings are closed under the decay rule, and they were never the trailing-index
shape anyway: each is a one-line pointer closing a numbered phase section, where the enclosing
heading supplies the *when* and the P3 fix supplied the *what*. Converting them to a table would
move phase-local routing away from the phase it routes.

**Applied 2026-08-26: 18 of 22, in ten trailing-index rewrites and eight inline when-clauses.**
Three sites were declined as no longer holding. `claude-ops` `morning-brief` ships no `context/` or
`reference/` directory at all, so its `## Cross-references` names two sibling-skill boundaries and
no spoke; `claude-ops` `observability`'s `## Cross-references` is a single disambiguation line, and
its real spoke index is the `## Context ladder (read on demand)` section this remediation copies as
a model. The `audit-encapsulation` shared-fallback sentence was fixed too, though the table counted
only five skills carrying it, so the sentence does not drift across the six.

**`plugins/planning/skills/interview/SKILL.md` is the one site left standing, and the reason is a
cost, not a doubt about the finding.** The blind pointer is real. It sits inside
`## What this skill does NOT do`, and `plugins/planning/tests/interview-defenses.test.sh` pins that
exact section by content digest, under the assertion `SKILL.md "does NOT do" section is unchanged
(the fudge prohibition lives here)`. Any fix re-baselines that digest, including the structurally
better fix of moving the misfiled reference row out of a prohibitions section, because removing the
line changes the digest too. The pin exists to make an unreviewed edit to a safety prohibition
fail loudly. Spending it on a pointer's when-clause trades a standing defense for a Tier 3 prose
improvement, so the finding stays open rather than being paid for at that price. **Re-opening it is
a human's call**: either accept a digest re-baseline for a cosmetic fix, or leave the pointer as it
is. The underlying misfiling, a reference row living under a prohibitions heading, is the more
useful thing to fix if anyone touches that section for another reason.

### `deep-nesting`, 6

| Path | Tier | Chain |
|---|---|---|
| `plugins/claude-config/skills/audit-pass/reference/terms.md` and `reference/finding-identity.md` | 2 | `plugins/claude-config/skills/audit-pass/SKILL.md:19` to `plugins/claude-config/skills/audit-pass/reference/run-contract.md:9` to leaf. Every other leaf opens by assuming `terms.md`, and it is the file furthest from the hub |
| `plugins/architecture/skills/improve/research/deepening/*.md` (5 files) | 2 | `plugins/architecture/skills/improve/SKILL.md:35` to `plugins/architecture/skills/improve/actions/deepening.md:26` to that skill's `research/deepening/scan-briefing.md`. The citing line calls the target load-bearing for scan quality |
| `plugins/session-flow/skills/retro/reference/ecosystem-improvement-catalog.md` | 2 | `plugins/session-flow/skills/retro/SKILL.md` to `plugins/session-flow/skills/retro/context/session.md:184` ("Load the catalog") to the catalog |
| `plugins/knowledge/skills/course-digest/reference/screenshot-strategy.md` | 2 | `plugins/knowledge/skills/course-digest/SKILL.md` to `plugins/knowledge/skills/course-digest/context/workflow.md:46` to the strategy |
| `plugins/claude-ops/skills/known-issues/context/issue-templates.md`, `context/output-templates.md` | 3 | Explicitly conditional offline snapshots. Alternates, not required reading. **No treatment** |
| `plugins/songwriting/context/pat-pattison/research/book-references.md` | 3 | Shared bibliography cited by its siblings. Legitimate cross-reference. **No treatment** |

### `orphan-spoke`, 4 in a tree of 507

| Path | Status |
|---|---|
| `plugins/ai-briefing/skills/generate/context/execution-flow.md` | **Resolved.** Deleted in the sweep after four rules were salvaged into `SKILL.md` |
| `plugins/implementation/skills/implement/context/gotchas.md` | **Open.** Dead within its skill: its three siblings are cited from the mode table at `plugins/implementation/skills/implement/SKILL.md:43-45`, it is not, and `:210` of that same file carries a `## Gotchas` heading inline instead. Add the pointer and move the inline entries into the file |
| `plugins/songwriting/skills/suno/reference/suno-drift-audit-ledger.md` | **Open.** Maintenance ledger, unreferenced. Add a pointer under a new maintenance section, or move to plugin scope |
| `plugins/knowledge/skills/video-digest/extraction/liveness/LIVENESS.md` | **No treatment.** Co-located script README beside `run-source-liveness.js`, not a disclosure spoke |

The count is 4 and not 132. `audit-progressive-disclosure`'s detector reported 132 before its
`md_links()` bug was fixed in 0.21.14; the 4 above were each verified by an independent repo-wide
reachability pass and by a targeted grep.

## L3 deduplication: 13 clusters remediated, 13 refused

Every remedy is an in-place fix against a file that already exists. **No cluster proposes a new SSOT
artifact**, and three that passed the Rule of Three were still resolved in place. Nothing here was
applied.

### Remediated, N greater than or equal to 3

| Cluster | Instances | Existing owner | Remedy |
|---|---:|---|---|
| `lane-telemetry-upsert` | 3 | `plugins/claude-ops/skills/lanes/SKILL.md`, "Never pass a body as an `@path` string" | `name-an-owner` plus `normalize-wording`. Highest value in the lane: drifted, unowned, unguarded |
| `dynamic-context-git-preamble` | 44, 26 edited | none; proposes a `docs/PLUGIN-PHILOSOPHY.md` "Inline-template conventions" home | `normalize-wording` plus `edit-existing-rule`. One canonical fallback string corrects a live mislabel (`echo "clean"` on a failed `git status`) at 15 sites |
| `setup-probe-dont-recite` | 17 | `docs/PLUGIN-PHILOSOPHY.md` "Setup is explicit and repeatable" (clause absent) | `edit-existing-rule`. All 17 already cite that contract at document scope |
| `setup-headless-reconfigure-recipe` | 22, 6 edited | `docs/PLUGIN-PHILOSOPHY.md` "Configuration ownership and scope" | `normalize-wording` |
| `detector-findings-producer-preamble` | 4 | `docs/conventions/detector-findings/README.md` | `normalize-wording`. Removes two em dashes in `plugins/mutation-testing/skills/audit/context/persist-findings.md:1` and `:5` as a side effect |
| `songwriting-persistence-block` | 9 | `plugins/songwriting/context/pat-pattison/research/artifact-persistence.md` | `trim-to-citation`, the lane's only one, because it is the only cluster whose owner sits inside the same plugin as its call sites |
| `setup-never-writes-boundary` | 41, 34 edited | `docs/PLUGIN-PHILOSOPHY.md` "Configuration ownership and scope" | `normalize-wording` |

### Remediated, N equal to 2 and N equal to 1

| Cluster | Sites | Remedy |
|---|---|---|
| `statusline-shim-durable-wiring` | `context-guard` / `rate-limit-guard` setup skills plus READMEs | `name-an-owner`. No owner declared and the scripts have already drifted |
| `toolchain-remote-resolution-snippet` | `toolchain:check` / `toolchain:lint` | `name-an-owner` |
| `prototype-throwaway-constraints` | `prototype:explore-directions` / `prototype:pressure-test` | `name-an-owner` |
| `github-read-only-posture` | `github:advise` / `github:audit` | `name-an-owner` |
| `marketplace-bootstrap-placeholders` | `dometrain` / `miro` setup skills | `edit-existing-rule` plus `normalize-wording` |
| `planning-setup-uncited-reconfigure-recap` | `plugins/planning/skills/setup/SKILL.md:120-141` | `normalize-wording` plus a provenance citation. The only setup skill of 51 carrying the reconfiguration block with no citation anywhere in the file |

### Refused, 13 clusters and roughly 197 instances

Recorded so nobody re-opens them.

| Cluster | Instances | Refusal ground |
|---|---:|---|
| `plugin-lifecycle-artifact-protocol` | 6 | Registered cluster, CI check `validate-plugin-contracts.mjs` |
| `standards-contract-mirror` | 3 | Registered cluster, CI check `sync-standards-contract.sh` |
| `plugin-options-generated-block` | 34 | Generator-owned, `sync-plugin-options-docs.py` |
| `fleet-changelog-entries` | 64 | Per-plugin historical record |
| `untrusted-content-spine` | ~18 | Convention mandates inline carry, with a conformance sweep |
| `rate-limit-guard-floor-inline` | 4 | Declared inline-floor rule, provenance-only citation, byte-identical |
| `autonomy-routine-axis-scaffolding` | 10 | Every row cites its owner; per-identity table data; no drift |
| `discovery-agents-tool-honesty` | 3 | Locked by `plugins/discovery/agents/tool-honesty.test.sh` |
| `topic-docs-plugin-slices` plus the discovery/verification setup pair | 12 | Cited convention slices; the pair carries a recorded prior refusal |
| `formatter-readme-requirements` | 12 | EXPOSE surface, primary-source URL, no drift |
| `commit-convention-well-known-path` | 4 | Template-owned, byte-identical to the emitting template |
| `setup-write-vs-session-effect` | 18 | 17 of 18 already carry a document-scope citation |
| `songwriting-author-seam` | 9 | 9 of 9 already cite by exact heading |

**Sequencing.** Roughly 45 `plugins/*/skills/setup/SKILL.md` files are touched by four sub-clusters
at once and must be worked one pass per file, not in parallel. `docs/PLUGIN-PHILOSOPHY.md` carries
three clusters' owner additions and must go first, because every later cluster cites it.

## L4 encapsulation: 34 violations

The other 55 of the audit's 89 dissolved under
[ADR 0018](../adr/0018-treat-the-plugin-as-the-encapsulation-boundary-for-skill-citation.md). These
34 do not. All 34 `path:line` citations were re-verified on 2026-08-26 and every one resolves to the
citing text the audit quoted.

### Group 1. Cross-plugin and out-of-plugin, 24

Unchanged by ADR 0018. The remedy is `/plugin:skill <action>` routing, or promoting the cited
content to `plugins/<p>/reference/` or a `docs/conventions/` entry, which sit outside every skill
directory and are legal cite targets.

| # | Citing `path:line` | Cited private surface |
|---|---|---|
| `V-review-01` | `docs/conventions/detector-findings/README.md:9` | `review/skills/fanout/context/default-mode.md` |
| `V-review-02` | `docs/conventions/detector-findings/README.md:79` | `review/skills/fanout/context/fix-pass-mode.md` |
| `V-review-03` | `docs/conventions/detector-findings/README.md:83` | `review/skills/fanout/context/findings-normalization.md` |
| `V-review-04` | `docs/conventions/detector-findings/README.md:109` | `review/skills/fanout/context/findings-normalization.md` |
| `V-review-05` | `docs/conventions/detector-findings/README.md:261` | `review/skills/fanout/context/fix-pass-mode.md` |
| `V-review-06` | `docs/conventions/detector-findings/README.md:303` | `review/skills/fanout/context/fix-pass-mode.md` |
| `V-review-07` | `docs/conventions/detector-findings/README.md:482` | `review/skills/fanout/context/fix-pass-mode.md` |
| `V-review-08` | `docs/conventions/detector-findings/README.md:497` | `review/skills/fanout/context/fix-pass-mode.md` |
| `V-review-09` | `docs/conventions/detector-findings/README.md:506` | `review/skills/fanout/context/fix-pass-mode.md` |
| `V-review-10` | `docs/conventions/detector-findings/README.md:628` | `review/skills/fanout/context/default-mode.md` |
| `V-review-11` | `docs/conventions/detector-findings/README.md:629` | `review/skills/fanout/context/fix-pass-mode.md` |
| `V-review-12` | `docs/conventions/detector-findings/README.md:631` | `review/skills/fanout/context/findings-normalization.md` |
| `V-review-13` | `docs/conventions/native-references/README.md:127` | `review/skills/quality-gate/context/pr.md` |
| `V-review-14` | `docs/conventions/native-references/README.md:183` | `review/skills/quality-gate/context/pr.md` |
| `V-slop-01` | `.claude/rules/vendor-docs-are-not-style.md:10` | `ai-slop/skills/audit/reference/rewrite-guide.md` |
| `V-slop-02` | `docs/conventions/upstream-drift/README.md:342` | `ai-slop/skills/audit/reference/catalog.md` |
| `V-dhg-01` | `docs/conventions/upstream-drift/README.md:343` | `docs-hygiene/skills/write-for-humans/reference/sources.md` |
| `V-sf-01` | `docs/conventions/pre-pr-ordering/README.md:5` | `session-flow/skills/workflow/context/pre-pr.md` |
| `V-sq-01` | `docs/PLUGIN-PHILOSOPHY.md:596` | `skill-quality/skills/check/reference/fresh-eyes-declarations.md`, also unresolvable |
| `V-sq-02` | `docs/PLUGIN-PHILOSOPHY.md:1071` | same target, also unresolvable |
| `V-sc-15` | `plugins/work-items/skills/setup/reference/overlay-ignore-probes.md:18` | `source-control/skills/setup/reference/apply-convention.md` |
| `V-ops-01` | `plugins/claude-config/skills/audit-pass/reference/run-state-and-resumability.md:70` | `claude-ops/skills/lanes/context/restart-consumer.md` |
| `V-auto-01` | `plugins/source-control/skills/babysit-loop/reference/promotion-evidence-resolution.md:8` | `autonomy/skills/setup/schemas/guardrails-security-binding.schema.json` |
| `V-ct-01` | `plugins/claude-config/skills/audit-instructions/reference/criteria.md:392` | `code-tidying/skills/tidy/reference/tidyings.md` |

Three of these deserve their own note.

`V-slop-01` is the only Tier 1 entry in the whole sweep: an always-loaded rule sends every agent in
every session to a private reference. `V-review-01` through `V-review-12` are the only case in the
corpus where the dependency is stated as a contract rather than written as a convenience: a
repo-level convention other plugins implement names three `review:fanout` private files as its
"External authority". `V-auto-01` is the corpus's only schema-file citation, and the contract's
treatment at
`plugins/docs-hygiene/skills/audit-encapsulation/context/public-surface-contract.md:37` is
unambiguous:

```text
Schema files (`*.schema.json`) stay private — route via `/skill-name <action>` or vendor the schema to a shared tooling location the consumer repo owns.
```

Four of the 24 are skill-body reaches that cross a plugin boundary and are therefore filed under the
dissolved sibling-reach class in the audit's own roll-up: `V-sc-15`, `V-ops-01`, `V-auto-01`,
`V-ct-01`. They are not dissolved.

### Group 2. Intra-plugin citations that do not resolve as written, 8

Legal as citations under ADR 0018, defective as paths. **The fix is form, not routing:** rewrite each
to the anchored `${CLAUDE_PLUGIN_ROOT}/skills/<s>/<path>` form, which
`plugins/discovery/reference/parent-contract.md:15-17` already uses correctly for three of the same
targets, or add the `../` the `plugin-root` form is missing.

| # | Citing `path:line` | Path as written | Resolves to |
|---|---|---|---|
| `V-sc-01` | `plugins/source-control/reference/config-resolution.md:179` | `skills/babysit-loop/reference/promotion-evidence-resolution.md` | `plugins/source-control/reference/skills/...`, absent |
| `V-sc-02` | `plugins/source-control/reference/review-discipline.md:306` | `skills/babysit-loop/reference/pre-escalation-dispatch.md` | same shape, absent |
| `V-sc-03` | `plugins/source-control/reference/review-discipline.md:171` | `skills/babysit-prs/reference/safety.md` | same shape, absent |
| `V-sc-04` | `plugins/source-control/reference/review-discipline.md:271` | `skills/babysit-prs/reference/safety.md` | same shape, absent |
| `V-sc-05` | `plugins/source-control/reference/review-discipline.md:303` | `skills/babysit-prs/reference/independent-resolution.md` | same shape, absent |
| `V-disc-04` | `plugins/discovery/reference/topic-docs.md:88` | `skills/explore/reference/dispatch.md` | `plugins/discovery/reference/skills/...`, absent |
| `V-disc-05` | `plugins/discovery/reference/topic-docs.md:88` | `skills/research/context/dispatch.md` | same shape, absent |
| `V-disc-06` | `plugins/discovery/reference/topic-docs.md:89` | `skills/trace-intent/context/dispatch.md` | same shape, absent |

### Group 3. Heading anchors, 2

Both intra-plugin, both currently resolving, both outside ADR 0018's reach because an anchor binds
body structure rather than file layout.

| # | Citing `path:line` | Cited anchor |
|---|---|---|
| `V-sc-17` | `plugins/source-control/reference/worktree-root-convention.md:66` | `../skills/worktree/SKILL.md#the-nesting-invariant-verified` |
| `V-dh-01` | `plugins/disk-hygiene/README.md:190` | `skills/clean/reference/safety-model.md#standalone-git-checkout-evidence` |

`V-sc-17` has a genuine case for a narrow anchor carve-out rather than a rewrite:
`plugins/source-control/skills/worktree/SKILL.md:54` claims canonical ownership of that section for
the whole plugin fleet and says every other surface in the plugin points there instead of restating
it, which is a skill publishing an anchor as an interface. ADR 0018 declines to open that carve-out.

### Not remediated and not counted

57 intra-plugin citations would benefit from normalising to the anchored form. That is tidy-up, not a
defect, and it is not part of this set. Eight of them are in group 2 because they are also broken.

## L5 noise: 10 findings

All Tier 2 except the `plan-reference` finding, which is Tier 1. Treatment is never a deletion; the
constraint survives the rewrite. Line numbers below are **re-verified against the working tree on
2026-08-26** and differ from the audit's own where a file has since moved.

### `negation`, 6

**1. `docs/PLUGIN-PHILOSOPHY.md:561`** (the audit recorded `:546`; the file gained 15 lines above it)

```text
Do not swallow errors or claim success when the promised result was not produced.
```

No positive anywhere in the paragraph. Replacement:

```text
Surface every error, and report the result the run actually produced.
```

**2. `plugins/review/skills/fanout/context/fix-pass-mode.md:142`**

```text
- **NEVER route correctness findings to `/simplify`.**
```

A whole bullet with no positive. The destination for a correctness finding is left unstated.
Replacement:

```text
- **Route correctness findings to the fix pass. `/simplify` is quality-only and does not hunt bugs.**
```

Confirm the destination against the fix pass's own routing table before applying.

**3. `plugins/instruction-placement/skills/realign/context/apply-recipes.md:70`**

```text
**Never** put an `@import` in the body of a path-scoped rule. The import inlines at session start and
defeats the scoping — the move would read as a saving and not be one.
```

The second sentence is rationale, not an alternative. Replacement for the first sentence, keeping
the second verbatim:

```text
**Cite** the shared file from a path-scoped rule by path, never with an `@import`: the import
inlines at session start and defeats the scoping.
```

**4. `plugins/adhd/skills/shape/SKILL.md:39-40`** (the audit recorded `:38-39`)

```text
1. **Working memory is small.** Anything off-screen is gone. Never ask the
   reader to "keep in mind" something stated earlier.
```

The positive form is the skill's own standing rule, stated in its `description` as "restate state
across turns". Replacement for the third sentence:

```text
Restate any earlier state the reader needs, in the current response.
```

**5. `plugins/source-control/skills/babysit-prs/SKILL.md:321`**, sentence-final on the line

```text
Never block a safe iteration on the engine's absence.
```

The preceding clause covers reporting, not proceeding, so the positive is genuinely absent.
Replacement:

```text
Let a safe iteration proceed when the engine is absent, reporting merge-readiness as unchecked.
```

**6. `plugins/source-control/skills/babysit-prs/reference/loop.md:629`**

```text
- **Do not skip verification steps.** The D5/D6/D7 verification sub-steps exist because model
  memory is unreliable across compaction boundaries.
```

Replacement for the bolded lead, the rationale sentences surviving verbatim:

```text
- **Run the D5/D6/D7 verification sub-steps on every pass.**
```

### `ghost-ref`, 3

All three are paths that have never existed for any reader other than the original author: a pruned
topic slice, and two `.work/` paths that are gitignored at `.gitignore:29`.

**1. `docs/specs/invocation-mode-doctrine-brief.md:5`**, lines 5 to 7:

```text
`docs/topics/pocock-course-lanes/PLAN.md` on branch `claude/plan-mode-discussion-55kszx`, steering
rows now in `docs/upstream/aihero-course.md` — the interim steering record dissolved into it at
the lane 6 harvest).
```

The sentence already carries its own durable replacement one clause later. Replacement:

```text
chain contract: the steering rows in `docs/upstream/aihero-course.md`, which the interim
steering record dissolved into at the lane 6 harvest).
```

**2. `docs/specs/invocation-mode-doctrine-brief.md:8`**, lines 7 to 8:

```text
Interview ledger:
`.work/invocation-mode-doctrine/interview-checklist.md` (8/8 answered, register gate clean).
```

The parenthetical carries the whole load. Replacement:

```text
Interview ledger: 8/8 answered, register gate clean (memory tier, not committed).
```

**3. `docs/specs/write-for-agents-brief.md:6`**, lines 5 to 8:

```text
answered, register gate clean, **user confirmed the shared understanding 2026-08-17**). Working
ledger: the topic's memory slice (`.work/authoring-steering-skill/`, disposable). The verified
auto-read enumeration feeding the scope statement lives in that slice's `RESEARCH.md` artifact
set; its durable adaptation lands in the skill's reference file at implementation.
```

Worse than finding 2: this one sends the reader into an unrecoverable path for the evidence behind
the scope statement. Replacement for the last two sentences:

```text
The verified auto-read enumeration behind the scope statement lands in the skill's reference
file at implementation.
```

If that enumeration is load-bearing evidence rather than working notes, promote it into the brief
instead of stripping the pointer.

### `plan-reference`, 1

**`plugins/source-control/skills/babysit-prs/reference/loop.md:56`** (Tier 1), lines 56 to 59:

```text
**Draft policy (replaces the old blanket draft skip):** drafts stay in the discovery list in
every tier. In the safe tier a draft is evaluated — terminal state, CI, unaddressed findings —
and reported, never fixed, never marked ready. Worker/autopilot draft handling (zero-blocker
drafts route through a worker; `gh pr ready` only in autopilot) is defined in SKILL.md.
```

The parenthetical narrates the changeset that produced the policy. No reader of this file has the
old blanket draft skip to compare against. Delete the parenthetical only. Replacement for the bolded
lead, the rest of the paragraph surviving verbatim:

```text
**Draft policy:** drafts stay in the discovery list in
```

## L6 compression: 1 finding

**`plugins/overengineering/skills/delta/context/recurring-wiring.md:83`.** One stacked-hedge
intensifier, 6 bytes. Verified still present on 2026-08-26.

```text
own audit will later walk, judge on carry cost, and quite possibly recommend retiring. Wire it
```

Drop `quite`. This is the only proposed cut in the whole sweep that is a plain markdown edit, and it
still needs the semantic-diff gate that `docs-hygiene:compress` makes mandatory.

**Settled disposition, 2026-08-26: declined, and this row is closed rather than open.** Two gates
were run against it and both decline it.

`compress`'s own ship rule is `<3% AND 0 semantic-loss → REVERT` (`SKILL.md` "Flags", where `--force`
exists precisely so a user can own a sub-3% diff). Dropping `quite` is 6 bytes against a file of
several kilobytes, roughly 0.1%, and carries no semantic loss by construction. So the skill that
proposed the cut is the same skill that reverts it. Nothing in the sweep's scope supplied the
`--force` that would override that.

The second gate was the independent one. `ai-slop`'s `rule-stacked-hedging` detector was run
directly against the file and returned zero findings across all fourteen of its rules. So "quite
possibly" is not a hedge this repo's own prose standard recognises, and the finding has no
justification outside `compress` either.

Applying it anyway would have meant a one-word commit that the proposing skill's ship gate rejects,
justified by a prose rule that does not fire. Re-opening this row needs a new argument, not a
re-reading of the old one.

Two more were held at SKIP and are flagged for `write-for-humans` rather than compression, because
the shorter form needs the surrounding clause re-punctuated, which is a rewrite rather than a word
drop: `plugins/architecture/skills/improve/actions/deepening.md:56` and
`plugins/event-storming/skills/methodology/reference/big-picture-workshop.md:224`, both carrying
`in terms of`.

## L7 write-for-agents: 13 findings

All 13 `path:line` citations were re-verified on 2026-08-26 and every one resolves to the quoted
text exactly.

### P3, a pointer opens on the routing verb instead of the matching term, 11

| # | `path:line` | Tier | Verbatim | Replacement |
|---|---|---|---|---|
| B-1 | `plugins/claude-ops/skills/audit-install-state/SKILL.md:152` | T2 | `See [reference/surfaces.md](reference/surfaces.md).` | `Per-path retention rules: see [reference/surfaces.md](reference/surfaces.md).` |
| B-2 | `plugins/claude-ops/skills/audit-install-state/SKILL.md:170` | T2 | `See [reference/name-schemes.md](reference/name-schemes.md).` | `Name schemes and their liveness meanings: see [reference/name-schemes.md](reference/name-schemes.md).` |
| B-3 | `plugins/claude-ops/skills/audit-install-state/SKILL.md:205` | T2 | `See [reference/evidence-discipline.md](reference/evidence-discipline.md).` | `Cross-review procedure: see [reference/evidence-discipline.md](reference/evidence-discipline.md).` |
| B-4 | `plugins/claude-ops/skills/audit-install-state/SKILL.md:213` | T2 | `See [reference/evidence-discipline.md](reference/evidence-discipline.md) §6.` | `Upstream-claim verification: see [reference/evidence-discipline.md](reference/evidence-discipline.md) §6.` |
| F-1 | `plugins/mutation-testing/skills/principles/SKILL.md:48` | T2 | `See [scaling-and-suppression.md](reference/scaling-and-suppression.md).` | `Scaling and suppression mechanics: see [scaling-and-suppression.md](reference/scaling-and-suppression.md).` |
| F-2 | `plugins/testing/skills/run-e2e/context/e2e.md:35` | T3 | see below | see below |
| H-1 | `plugins/discovery/skills/research/SKILL.md:159` | T2 | `See the discipline file's "Tool-ecosystem Phase 3 fallback" for the playbook.` | `Tool-ecosystem Phase 3 fallback playbook: the discipline file's "Tool-ecosystem Phase 3 fallback".` This file cites the same target seven times and front-loads the term every other time; line 159 is the single deviation |
| J-1 | `plugins/playwright/skills/playwright/reference/storage-and-auth.md:53` | T3 | `See [running-code.md](running-code.md).` | `Running arbitrary page code: see [running-code.md](running-code.md).` |
| J-2 | `plugins/playwright/skills/playwright/reference/commands.md:52` | T3 | `See [snapshots-and-refs.md](snapshots-and-refs.md) for ref system.` | `Ref system: see [snapshots-and-refs.md](snapshots-and-refs.md).` |
| J-3 | `plugins/playwright/skills/playwright/reference/commands.md:129` | T3 | see below | see below |
| I-1 | **104** pointers across **26** files under `plugins/songwriting/context/pat-pattison/` and `plugins/songwriting/skills/suno/context/`. Recorded as 31 across 16; that count was wrong, corrected below | T3 | Routing verb opens the unit, in two sub-shapes | **Settled 2026-08-26: declined. The files are left untouched.** Grounds and the corrected census are held out of the table below, along with a two-site residual that this decline does **not** cover and that stays open |

B-1 through B-4 also fail L2's blind-pointer shape. If L2's fuller rewrite is applied, drop these
four rather than applying both.

**F-2**, held out of the table because it carries nested code spans. Verbatim at
`plugins/testing/skills/run-e2e/context/e2e.md:35`:

```text
**See `/playwright:playwright`** (when the playwright plugin is installed) for CLI mechanics — commands, sessions, snapshots, storage, tracing, network mocking, Windows quirks. This skill (`/testing:run-e2e`) owns the broader orchestrator + API + UI story.
```

The pointer covers its branches (condition, payload, complement), so it passes the branch predicate.
It fails only on the bolded leading token being the routing verb. Moving the emphasis fixes it
without touching the content, and removes an em dash as a side effect:

```text
**CLI mechanics** (commands, sessions, snapshots, storage, tracing, network mocking, Windows quirks): see `/playwright:playwright`, when the playwright plugin is installed. This skill (`/testing:run-e2e`) owns the broader orchestrator + API + UI story.
```

**J-3**, same reason. Verbatim at
`plugins/playwright/skills/playwright/reference/commands.md:129`:

```text
See [sessions.md](sessions.md) for `-s=<name>` session isolation; [windows-quirks.md](windows-quirks.md) for `--headed` on Windows.
```

Both halves state their payload, so only the opening routing verb fails. Replacement:

```text
Session isolation with `-s=<name>`: see [sessions.md](sessions.md). `--headed` on Windows: see [windows-quirks.md](windows-quirks.md).
```

**I-1, settled 2026-08-26: declined.** The files are left untouched and this row is closed. What
follows is the whole basis, including a corrected census, so that re-opening it needs a new argument
rather than a re-reading.

**The recorded count was wrong, and so was the first correction of it.** A paragraph-first census of
both trees (soft-wrapped lines joined into logical units, code fences and `>` blockquotes stripped,
requiring a link or a cited `.md` target immediately after the verb) finds **104** sites where a
routing verb opens the reading unit or the sentence, across **26** files. Not 31 across 16. An
earlier pass that matched verb and target on the same physical line reported 72 across 23, and was
wrong for a reason worth recording: roughly a quarter of these pointers wrap, with `See` ending one
line and its link opening the next. Any re-run must join wrapped lines before counting.

Two anchors make the census checkable without re-implementing it. Both are exact:

- **110.** Occurrences of capital `See` outside `>` blockquotes across the two trees. That is the
  ceiling; the census keeps 104 of them and drops the rest as parenthetical or mid-sentence.
- **52.** `research/workflows.md` holds 52 sites, exactly half the population, and that equals every
  capital `See` in the file. No judgment call moves that number.

| Sub-shape | Sites | Files | Example |
|---|---:|---:|---|
| `See <link> for <payload>` | ~32 | 20 | `See [meter](meter.md) for the stress notation this depends on.` |
| Bare pointer, no payload to move | ~72 | 17 | `See [hook](hook.md).` |

The headline 104 and the two-way split carry about a site or two of method sensitivity at the
margin: an independent re-count landed at 105 and split it 34 / 71, differing only on a handful of
table-cell and bolded-lead boundaries where "does the unit start here" is a judgment call. Treat 104
as accurate to plus or minus 2 and the two anchors above as exact. Nothing in the disposition turns
on the difference. Also deliberately outside the count, so a re-run does not re-add them: 8
parenthetical citations of the form `(see point-of-view.md)`, which already front-load their payload
and are the correct form rather than the defect; mid-sentence uses where the payload precedes the
verb; and every hit inside quoted book text under `>`.

**Half the population has no payload to front-load, and its reading unit is already correct.** 72 of
the 104 are bare pointers, and 52 sit in `research/workflows.md`, a numbered checklist where every
step opens on a bolded term that carries the routing decision by itself:

```text
9. **Hook check** — is the title in a hot spot? Has hook rhythm been
   established before the title arrives? See [hook](hook.md).
```

The prescribed transform, `<payload>: see <link>.`, yields `Hook: see [hook](hook.md).`: a tautology
that front-loads nothing `**Hook check**` did not front-load two lines earlier, and that discards
the step's question in the process. The reading unit here is the numbered step, not the sentence,
and the step already satisfies the doctrine. Applying the transform to these would mean inventing
payload text, which is a content edit rather than a formatting one, inside a tree whose `README.md`
declares fidelity to a third party's printed material.

**All-or-none is therefore none.** The lane's own condition was "apply all in one edit or none". 52
of the 104 cannot take the transform at all, so "apply all" is not an available option. Applying
only the 32 `for <payload>` sites produces exactly the outcome the lane warned against, two competing
pointer styles inside one reading path, because `workflows.md` is the hub that routes into
`prosody.md`, `hook.md`, `five-compositional-elements.md` and the rest, and those are where most of
the 32 live. The lane's structural instinct was right even though its facts were not.

**On the doctrine itself.**
`plugins/docs-hygiene/skills/write-for-agents/SKILL.md`, "Write pointers that cover their branches",
states the rationale P3 serves: "A pointer is a routing instruction; the reader decides whether to
follow it from the pointer text alone, without opening the target." Its rule, verbatim:

```text
- **Front-load the leading word.** Open with the term the reader is matching on ("Deploys:
  see…", never "See the following doc for information about deploys").
```

Taken literally, a pointer opening `See` on a bracketed link fails that rule; that much is
conceded, and this decline does not rest on arguing otherwise. What it rests on is the rationale.
The doctrine's own counter-example names its target contentlessly ("the following doc") and buries
the term at the end, so a reader cannot route without opening it. Here the link text *is* the domain
term (`hook`, `cliche`, `meter`, `rhyme types`) and it sits in word two, or else the bolded step
label above it carries the term. The routing decision is available from the pointer text in every
one of the 104. The letter is violated; the purpose is not. That is a real but low-grade defect, and
it is what S3 means.

**Not vendor material, and that cuts against the row rather than for it.**
`plugins/songwriting/context/pat-pattison/` is not under `plugins/*/skills/*/vendor/**`, so
`.claude/rules/vendor-docs-are-not-style.md` grants it no exemption, and `.claude/ai-slop.json`'s
`excluded_paths` does not list it either: the tree is audited as this repository's own prose. The
decline therefore rests on the doctrine's purpose being met, never on an exemption. What the tree
does carry is a standing owner ruling against zero-content sweeps of this kind, at
`plugins/songwriting/context/pat-pattison/research/book-references.md:18`: "Do not sweep, measure,
audit, or open work items on punctuation glyphs ... Spend the effort on missing content, invented
content, and wrong citations instead." That ruling is scoped to glyphs and does not itself decide
word order, but the cost it records does apply: per `.claude/ai-slop.json`, the changelog-parity gate
treats any edit under `plugins/<name>/` as version reuse, so this batch would publish a `songwriting`
release for a reordering that adds no information to any pointer.

**Tier.** Both trees are on-demand (T3) per
`plugins/docs-hygiene/skills/audit-progressive-disclosure/context/tier-model.md`, "The three tiers",
where bundled `context/` and `reference/` files are "Zero cost until read". `write-for-agents` grades
its own force by that cost: "the auto-read surfaces (CLAUDE.md scopes, `.claude/rules`, auto-memory,
and their kin) are the high-value core because their cost recurs every session ... Write differently
for an always-loaded surface than for an on-demand one." The doctrine applies at T3, but not with
T2's force, and nothing in these 104 clears the lower bar.

**The residual: two sites that are not covered by this decline, and are now APPLIED.** Two sites
matched the doctrine's counter-example rather than merely its letter, because the target was named
contentlessly and the payload trailed it: `plugins/songwriting/skills/suno/context/troubleshoot.md`
at `:65` and `:158`. Both opened `See` on a link whose text was the bare filename `SKILL.md`, then
trailed the payload ("on where first-hand observations sit relative to the ladder"). Unlike the
other 102, there was a real payload to move, so front-loading them was a clean, meaning-preserving
transform.

Both shipped in the same change set as this record, reading:

```text
Where a first-hand observation sits relative to the confidence ladder: see [Confidence flags](../SKILL.md).
```

The link text names the target section rather than the file, which is the half the counter-example
was actually about.

They were never declined. They were adjudicated inside a 104-site batch they do not belong to, and
the cost argument that governs the batch never governed them: `plugins/songwriting/` was already
being bumped for the `suno` orphan-spoke fix in the same change set, so the release these two would
have "cost" was already being published.

### P7, a step defers a fact it needs to an unnamed location, 2

**B-5. `plugins/claude-config/skills/audit/SKILL.md:90`** (T2, S2). Lines 88 to 90:

```text
Record the installed Claude Code version (`claude --version`). Phase 3.2 compares issue-fix versions
against it. Then run `bash "${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/check-structure.sh"`
before the table below.
```

"The table below" is 35 lines and two subsections away, with other tables above and below it, so it
does not resolve during execution. Replacement for line 90:

```text
before filling the `1.2 Structure inventory` table.
```

**D-1. `plugins/implementation/skills/implement/SKILL.md:71`** (T2, S1). The step commits; the rules
governing how it commits are in `### Commit discipline` at line 83, below an intervening section:

```text
4. **Commit checkpoint**. Commit after tests pass. Each commit should represent a green state. See below for commit discipline
```

Replacement:

```text
4. **Commit checkpoint**. Commit after tests pass. Each commit represents a green state; message shape and granularity are in "Commit discipline" below
```

The preferred alternative, if the L2 split of this file happens first, is to move the
`### Commit discipline` body up under step 4, which satisfies co-location outright. Pick one.

### One doctrine edit the lane could not make itself

`plugins/docs-hygiene/skills/write-for-agents/SKILL.md`'s "After writing" section says:

```text
- Resolved or coined a domain term? Invoke `/domain-driven-design:curate-language` via the
  Skill tool (if that plugin is installed), never hand-write a glossary entry.
```

The prohibition is unqualified; the skill it routes to is not. `curate-language` scopes itself to "a
consuming project's ubiquitous-language glossary" and excludes passive lookup. Six `AGENT` files
carry a hand-written vocabulary section that the prohibition catches and the routing target would
refuse: `plugins/event-storming/skills/methodology/reference/glossary-and-tools.md:3`,
`plugins/work-items/reference/execution-shape.md:111`, `plugins/review/context/severity.md:28`,
`plugins/architecture/skills/improve/research/deepening/vocabulary.md:7`,
`plugins/planning/skills/design/SKILL.md:144`, and
`plugins/songwriting/context/pat-pattison/research/book-references.md:182`. The defect is in the
doctrine sentence, not the six files. Proposed replacement:

```text
- Resolved or coined a term in the **consuming project's** domain? Invoke
  `/domain-driven-design:curate-language` via the Skill tool (if that plugin is installed) rather
  than hand-writing the entry. A skill defining its own working vocabulary is out of that skill's
  scope and stays where it is.
```

## L8 write-for-humans: 57 findings and 6 reclassifications

55 of the 57 sit in plugin READMEs. All 57 `path:line` citations were re-verified on 2026-08-26 and
every one resolves. The exact replacement text for each was written into the audit and is **not**
carried here; what is carried is enough to locate each finding and fix it without re-running the
scan, and the two largest classes are mechanical enough that the fix follows from the class.

The predicates: `Am1` a parenthetical is a full grammatical unit; `Am2` no `(s)` plurals; `Am3` no
slash coordination in prose; `Am4` `only` next to the word it changes; `L1` one thought per sentence;
`M1` one document one mode; `M2` release history belongs in the changelog; `M3` one place per
recurring block; `N1` one name per thing; `A1` command with its condition first.

### The two mechanical classes

**`Am1`, 18 findings.** A sentence ended *inside* a parenthetical, leaving a fragment on one side of
the period. The fix is the same every time: move the sentence break outside the parenthesis.
`plugins/adhd/README.md:105` is the model of the correct form and is not a finding. Every one of the
18 is in a plugin README and none is anywhere else in the corpus, which is the shape an automated
em-dash substitution produces when "end the sentence" is applied between parentheses. The worst is
`plugins/autonomy/README.md:183`:

```text
Setup writes tracked config to `.claude/autonomy/` in the consuming repo (concern-named. The
config outlives any plugin restructure).
```

**`M3`, 16 findings.** The marker-delimited `### Options reference` block generated by
`scripts/sync-plugin-options-docs.py` sits under 13 different `##` headings across 34 READMEs. Its
*placement* is authored even though its content is generated. The remediation is mechanical and
identical in all 16: move the block from `<!-- ai-slop-ignore-start: generated options block`
through the matching `<!-- END GENERATED` and its `ai-slop-ignore-end`, together with the
`### How to set these` subsection, under a `## Configuration` heading, adding that heading where the
plugin lacks one. **Do not edit the generated table.** The four least findable placements are filed
at S1: `## Sources` (`disk-hygiene`, where the same heading also means citations in every other
README), `## Tests` (`machine-health`), `## Revisit triggers` (`instruction-placement`), and
`## Possible future change` (`visualization`).

### Full index

| # | `path:line` | Predicate | Sev |
|---|---|---|---|
| A1 | `plugins/docs-hygiene/README.md:15` | `L1` | S2 |
| A2 | `plugins/docs-hygiene/README.md:18` | `L1` | S3 |
| B1 | `plugins/claude-ops/README.md:40` | `Am1` | S1 |
| B2 | `plugins/claude-ops/README.md:60` | `Am1` | S1 |
| B3 | `plugins/context-guard/README.md:109` | `Am1` | S1 |
| B4 | `plugins/guardrails/README.md:213` | `Am1` | S2 |
| B5 | `plugins/context-budget/README.md:78` | `M3` | S2 |
| B6 | `plugins/context-guard/README.md:127` | `M3` | S2 |
| B7 | `plugins/guardrails/README.md:338` | `M3` | S2 |
| B8 | `plugins/rate-limit-guard/README.md:119` | `M3` | S2 |
| B9 | `plugins/claude-config/README.md:125` | `L1` | S2 |
| B10 | `plugins/claude-config/README.md:157` | `L1` | S2 |
| B11 | `plugins/claude-ops/README.md:29` | `L1` | S2 |
| C1 | `plugins/disk-hygiene/README.md:54` | `M1`, `M2` | S2 |
| C2 | `plugins/disk-hygiene/README.md:196` | `M1` | S2 |
| C3 | `plugins/repo-fleet-hygiene/README.md:11` | `Am1` | S2 |
| C4 | `plugins/repo-hygiene/README.md:60` | `Am1` | S3 |
| C5 | `plugins/repo-fleet-hygiene/README.md:39` | `M2` | S2 |
| C6 | `plugins/disk-hygiene/README.md:299` | `M3` | S1 |
| C7 | `plugins/github/README.md:71` | `M3` | S2 |
| C8 | `plugins/source-control/README.md:274` | `M3` | S2 |
| D1 | `plugins/work-items/README.md:105` | `L1` | S2 |
| D2 | `plugins/planning/README.md:16` | `L1` | S2 |
| E1 | `plugins/autonomy/README.md:183` | `Am1` | S1 |
| E2 | `plugins/autonomy/README.md:89` | `Am1` | S1 |
| E3 | `plugins/discipline/README.md:130` | `Am1` | S1 |
| E4 | `plugins/discipline/README.md:149` | `Am1` | S1 |
| E5 | `plugins/discipline/README.md:150` | `Am1` | S1 |
| E6 | `plugins/discipline/README.md:273` | `Am1` | S1 |
| E7 | `plugins/discipline/README.md:376` | `Am1` | S2 |
| E8 | `plugins/discipline/README.md:381` | `Am1` | S2 |
| E9 | `plugins/autonomy/README.md:155` | `M2` | S2 |
| E10 | `plugins/discipline/README.md:3` | `M1` | S2 |
| E11 | `plugins/session-flow/README.md:3` | `L1` | S2 |
| F1 | `plugins/review/README.md:30` | `Am1` | S1 |
| F2 | `plugins/review/README.md:31` | `Am1` | S1 |
| F3 | `plugins/review/README.md:34` | `Am1` | S1 |
| F4 | `plugins/verification/README.md:44` | `Am1` | S2 |
| F5 | `plugins/bugs/README.md:127` | `M3` | S2 |
| G1 | `plugins/naming/README.md:14` | `L1` | S2 |
| G2 | `plugins/overengineering/README.md:149` | `L1` | S3 |
| H1 | `plugins/visualization/README.md:85` | `M3` | S1 |
| H2 | `plugins/miro/README.md:76` | `M3` | S1 |
| H3 | `plugins/dometrain/README.md:150` | `M3` | S1 |
| H4 | `plugins/ai-briefing/README.md:58` | `N1` | S3 |
| H5 | `plugins/visualization/README.md:15` | `L1` | S2 |
| H6 | `plugins/visualization/README.md:104` | `L1`, `Am3` | S2 |
| I1 | `plugins/songwriting/README.md:79` | `M2` | S2 |
| J1 | `plugins/machine-health/README.md:76` | `M3` | S1 |
| J2 | `plugins/instruction-placement/README.md:124` | `M3` | S1 |
| J3 | `plugins/skill-quality/README.md:111` | `M3` | S2 |
| J4 | `plugins/desktop-notification/README.md:85` | `M3` | S2 |
| J5 | `plugins/wizard/README.md:35` | `L1` | S2 |
| J6 | `plugins/plugin-quality/README.md:9` | `L1` | S2 |
| K1 | `docs/MIGRATION-PLAYBOOK.md:1728` | `Am3` | S3 |
| K2 | `docs/conventions/standards/README.md:80` | `Am3` | S3 |
| K3 | `docs/upstream/mattpocock-skills.md:14` | `Am2` | S3 |
| M1 | `README.md:54` | `Am4` | S3 |
| M2 | `SECURITY.md:9` | `A1` | S3 (no edit recommended) |

`K4` is `docs/PLUGIN-PHILOSOPHY.md`, filed as an `M1` mode finding with **no edit proposed**: it is
four documents (policy reference, argument, procedure, measured findings) in over a thousand lines,
and splitting it belongs to L2. The finding exists so L2 has the mode seams when it decides where the
split lines go.

Beyond the 14 adjudicated `L1` findings, all 442 raw `L1` hits are enumerated per group in the
audit. The filter was 45 or more words with 3 or more clause interrupters. Some of them will be long
sentences carrying one thought, which the resolved style guide protects, so judge each before
splitting.

### Two shapes worth naming

Both `M1` findings on `disk-hygiene` share one shape: **the heading names the process that produced
the content rather than the question the content answers.** `## Requirements and platform support`
is 81 lines of design-and-incident history, and `## Plugin-acceptance security review` is 103 lines
named for the review that was conducted rather than the posture the reader wants.

`I1` is the most delicate finding in the lane: a licence correction notice at
`plugins/songwriting/README.md:79` (`This wording changed in 0.8.6 because the previous version was
inaccurate`) inside `## License`. Its remediation moves three sentences **into** an already-released
changelog entry, which `scripts/check-changelog-parity.sh` gates on the correcting PR naming each
edit in its body and in the new release entry. Route that requirement to whoever writes the PR body.

### Reclassifications, 6

The manifest's `audience` column is a starting classification. These remove 74 of the 305 human rows,
a quarter of the slice, from authoring-doctrine scope, and account for at least 205 of the 442 raw
`L1` hits.

| # | Rows | Current | Recommended | Why |
|---|---:|---|---|---|
| R1 | 57 | `HUMAN` | out of scope, working artifact | `docs/topics/**`. Contract-tier documents whose reader is the task's own agents |
| R2 | 9 | `HUMAN` | `AGENT` | The `docs/conventions/*/README.md` files that declare themselves synced verbatim into agent-loaded plugin binding copies |
| R3 | 2 | `HUMAN` | `AGENT` | `prompts/**`. Launch-prompt templates filled in by a person and read by a model |
| R4 | 2 | `HUMAN` | out of scope, generated | `docs/CATALOG.md` and `docs/SKILL-CHEAT-SHEET.md` |
| R5 | 4 | `HUMAN` | out of scope, functional artifact | Test-fixture READMEs under `tests/fixtures/`, `skills/worktree/fixtures/`, `scripts/fixtures/` |
| R6 | 5 | `HUMAN` | no change, no findings filed | `docs/upstream/**` drift ledgers. A person does read them, but their table rows record what a source said and rewriting one changes the record |

### The 84 changelogs, judged once as a class

**Out of scope for authoring doctrine, no conformance rewrite, in this sweep or later.** Zero
findings. Four independent reasons, any one sufficient: a changelog entry is a dated record;
`scripts/check-skill-count-claims.sh` already excludes changelogs deliberately;
`scripts/check-changelog-parity.sh` gates the format so it is not a place doctrine ranges freely; and
that same script restricts in-place edits to an already-released entry to PRs that name each edit
twice. A conformance sweep editing 84 changelogs would owe that disclosure 84 times.

## Recall limits each lane declared

Carried verbatim in substance, because a finding count read as a defect count is worse than no count.
**No lane had a subagent-spawn tool.** Every lane ran serially in one context, substituting
corpus-wide mechanical detectors for fan-out, and every lane said so.

- **L2.** The 100-to-300-line `missing-toc` band (303 files) is contested between the two official
  sources and carries no treatment. Orphan and deep-nesting claims name their files precisely because
  the bundled detector's count was wrong by a factor of 33.
- **L3.** Line-anchored matching only, over 8-word normalized lines. It finds verbatim and
  near-verbatim reproduction and misses a paragraph asserting the same rule in different words.
  Hard-wrapped prose defeats it: two files stating one sentence with different line breaks share no
  normalized line, an unquantified hole in a corpus that wraps at roughly 100 columns. Tables and
  code fences were matched as ordinary lines. Changelogs were excluded from the block pass. **Roughly
  200 of 364 candidate blocks were triaged by first line and not individually verified.** The single
  change that would most improve a re-run is a shingled n-gram pass over whitespace-normalized text
  with line breaks removed entirely.
- **L4.** Prose references with no path are invisible to both passes and nothing estimates how many
  exist. Anchors are under-counted: only `#fragment` forms were caught, not sections pinned by
  quoting their title in prose. 81 candidates in `.sh`, `.yml` and `.json` fell outside the markdown
  corpus and got no remediation spec; two are worth a second look by whoever owns the shell surfaces,
  `plugins/source-control/scripts/babysit-readiness-gate.sh:53,88` and
  `plugins/skill-quality/scripts/check-skill.sh` at seven lines, both reaching a skill's private
  reference rather than through the `scripts/` entry surface the contract carves out. The 353 rows
  vacated as legal had one adjudicator and no second reader.
- **L5.** `negation` E3 recall is 7 of an estimated 120 (95% Wilson interval about 60 to 228). The
  1031-row remainder was sampled at n=60, not read, so roughly 113 genuine unpaired prohibitions
  exist in this corpus that the lane did not enumerate. **The lane deliberately did not issue the
  unread remainder**: at 11.7% sampled precision that would mean roughly 910 spurious edits to
  instruction surfaces. `enum-list` form decisions rest on 20-row reads each, backed by complete
  mechanical censuses. Six of the nine shapes were read in full with no sampling.
- **L6.** Article drops, passive-to-active conversions and nominalization rewrites are excluded
  deliberately, on a measured 9-of-9 revert record at 0.02 to 0.4% yield; the honest route for
  article drops is the skill's own default action on named files with the gate attached, not a spec.
  The verbose-form sweep is a fixed 15-form list, so recall on "all flavor" is well under 100% while
  recall on "the forms the matrix and the ai-slop catalog name" is complete. Quoted-text detection
  was line-based and biases toward SKIP. The 22 vendor files were never opened, and they are the
  corpus's most likely third-party pasted prose.
- **L7.** Recall is cue-bounded on every predicate and was never measured; precision was verified by
  reading every cue hit. P3 recall is bounded by a fixed routing-verb list, so a pointer opening
  `Look at`, `Check`, or `Head to` is missed. `T2` was a census and `T3` a sample for P7 and P9, so a
  `T3` violation of either is likely present and unfiled. P21 checked 5 fact families, not the space
  of harness claims. Four predicates are not text-auditable and were not attempted.
- **L8.** 24 files read in full, 61 read at the sections a mechanical hit pointed at, 220
  mechanically scanned only. `M1` recall is low because mode mismatch is judgment; `docs/native-surfaces/`
  in particular was scanned but not read. `Am4` recall is very low: 2 findings from roughly 900
  instances of `only`, applied by reading rather than by a proxy, because a proxy over that
  population would have reproduced the known cue failure. `N1` recall is low because one name per
  thing needs cross-file comparison, and only the plugin README class was compared systematically.
  Three specific claims the lane could not verify are flagged in place: the gate count at
  `plugins/skill-quality/README.md:117`, glosses supplied for table cells that have no text in the
  source today, and one `and/or` disambiguation that resolves an ambiguity rather than preserving it.
