# L1-derivability — corpus roll-up

Lane: `/docs-hygiene:audit-derivability`. Wave 1, read-only. Scope: all 1302 files in
`inventory/manifest.tsv`.

## Contents

- [Verdict counts](#verdict-counts)
- [The actionable set (what wave 3 consumes)](#the-actionable-set-what-wave-3-consumes)
- [Spot-test status: every deletion here is provisional](#spot-test-status-every-deletion-here-is-provisional)
- [Why the actionable set is this small](#why-the-actionable-set-is-this-small)
- [Cross-cutting patterns](#cross-cutting-patterns)
- [Cross-lane observations](#cross-lane-observations)
- [Method and coverage](#method-and-coverage)

## Verdict counts

| Verdict | Count |
|---|---:|
| `keep-owns-facts` | 1149 |
| `out-of-scope: functional artifact` (no verdict) | 141 |
| `keep-as-derivation-cache` | 10 |
| `delete` | 2 |
| `convert-to-pointer` | 1 |
| **Total** | **1302** |

Per group:

| Group | keep-owns-facts | cache | out-of-scope | delete | pointer |
|---|---:|---:|---:|---:|---:|
| `A-doc-quality` | 52 | 0 | 26 | 0 | 0 |
| `B-cc-config-ops` | 117 | 0 | 12 | 0 | 1 |
| `C-vcs-repo` | 82 | 0 | 10 | 1 | 0 |
| `D-work-planning` | 95 | 3 | 11 | 0 | 0 |
| `E-session-behavior` | 136 | 0 | 9 | 0 | 0 |
| `F-quality-verify` | 114 | 2 | 5 | 0 | 0 |
| `G-code-design` | 83 | 1 | 10 | 0 | 0 |
| `H-knowledge-research` | 111 | 1 | 20 | 1 | 0 |
| `I-songwriting` | 78 | 0 | 28 | 0 | 0 |
| `J-toolchain-platform` | 129 | 0 | 8 | 0 | 0 |
| `K-repo-docs` | 86 | 3 | 0 | 0 | 0 |
| `L-docs-topics` | 57 | 0 | 0 | 0 | 0 |
| `M-repo-root` | 8 | 0 | 2 | 0 | 0 |

## The actionable set (what wave 3 consumes)

Complete and exact. Three paths.

### `delete` (2)

```text
plugins/repo-hygiene/skills/clean/reference/ecosystems.md
plugins/ai-briefing/skills/generate/context/execution-flow.md
```

### `convert-to-pointer` (1)

```text
plugins/claude-ops/skills/known-issues/context/issue-templates.md
```

Both deletions carry a required companion edit (a dangling citation to drop, and two lines to
salvage). Full detail in `C-vcs-repo.md` and `H-knowledge-research.md`. The pointer target for the
conversion is verified present at `plugins/claude-ops/skills/known-issues/context/action-create.md`
lines 38 and 141.

## Spot-test status: every deletion here is provisional

The skill's hard rule requires a load-bearing `delete` to be confirmed by a fresh-context, non-fork
subagent that has not seen the document. **This session has no subagent-spawn tool.** `ToolSearch`
against the deferred-tool set returns `SendMessage`, `Monitor`, `TaskStop`, `EnterWorktree` and the
GitHub MCP surface; there is no `Task`/`Agent`/`Explore` tool to dispatch a fresh context to, and
`mcp__Claude_Code_Remote__create_session` spawns a separate container that cannot write into this
checkout's findings tree.

So per the skill's own contract both `delete` verdicts are **provisional**, not confirmed
actionable. The orchestrator must either run the spot-test in wave 2 from a context that can spawn
subagents, or apply them as the lower-risk `convert-to-pointer` instead. The
`convert-to-pointer` verdict needs no spot-test (its target was verified by direct read) and is
actionable as it stands.

## Why the actionable set is this small

Three independent reasons, each evidenced.

**1. This repo's markdown is the product, not a description of code.** Derivability asks whether a
fresh agent could reconstruct a document's conclusions from the repository's primary sources. In a
plugin marketplace the skill bodies, `reference/`, and `context/` files *are* the primary source.
There is no upstream code they restate. A mechanical scan for the index-restatement shape (a
document more than 45% of whose non-blank lines name a repo file) returns 6 hits across all 1302
files, and every one of the 6 is a deliberate manifest or ledger.

**2. The repo has already measured this exact deletion class and rejected it.**
`docs/specs/d1-model-already-knows-measurement.md:16` records the verdict of investigation #3121:

> **Routing finding — hand D1 to `claude-config:unhobble`, never rule on it.**

and at line 20:

> The proposed proxy fails at a rate that rules out deterministic scanning, and the reason it fails
> also rules out repairing it with a model-graded lane: the predicate is not an imprecise
> approximation of the right test, it is a proxy for a property that cannot be read off the text at
> all.

The measured false-positive rate was 94.1% over an 895-file agent-facing corpus that overlaps this
sweep's corpus almost exactly. Any verdict of mine that reduced to "the model already knows this"
would be landing in that 94.1%.

**3. A repo-wide derivability sweep already ran and was harvested.**
`plugins/docs-hygiene/context/derivability-route-followups.md:9` records the 2026-08-15 pass
(issue #2735): 1089 `keep-owns-facts`, 38 noise routes, 136 ssot routes, and pointer conversions
landed under #2695. One of those conversions,
`plugins/repo-hygiene/skills/clean/reference/ecosystems.md`, is the residue this pass now proposes
to finish removing. The cheap derivability debt in this corpus was already collected.

## Cross-cutting patterns

### `docs/topics/**` is live work, not spent residue

The brief flagged that many topic slices are "genuinely spent". They are not. All 57 files are
`keep-owns-facts`, and the reason is mechanical: nine of the eleven slices carry open phases.

| Slice | Open phases |
|---|---|
| `autonomy-ignition` | `PLAN.md:198` `### Phase 4: Accumulation watch [DOING — standing]` |
| `ladder-climb-roadmap` | Phases I, III, IV, V all `[TODO]` (`PLAN.md:92,200,211,223`) |
| `context-engineering-claude-5` | `PLAN.md:5` `Status: **in progress**`; Phases 10 and 11 `[TODO]` |
| `fresh-eyes-checkpoint-audit` | all four phases `[TODO]` (`PLAN.md:103,183,218,244`) |
| `plugin-audit-port` | `PLAN.md:443` `#### Phase B7: Operator cutover (post-merge, HITL) [TODO]` |
| `shadowed-skill-renames` | `PLAN.md` tail: `(To be filled by /planning:plan …)`, plus live `### Deferred questions` |
| `interview-batch-rounds` | `PLAN.md` tail: `<!-- empty — populated by /architect -->`, plus live deferred questions |

The two closed slices (`loop-engineering-codification`, `fable-field-guide-audit`) still own
non-derivable facts: withdrawn recommendations
(`docs/topics/loop-engineering-codification/PLAN.md:127` "The earlier `pull_request.closed`
recommendation is withdrawn rather than narrowed"), an operator's declined items
(`docs/topics/fable-field-guide-audit/repair-ledger.md:21` "**dropped** — a proposed remediation the
operator declined. No edit, and it is not deferred work"), and a captured external artifact
(`docs/topics/fable-field-guide-audit/source-article.md`, a web article the repo holds nowhere
else).

**These slices are already owned by a different program.** `scripts/contract-slice-baseline.txt`
grandfathers exactly these eleven slugs and states the exit condition:

> Done when this file lists no slugs and docs/topics/ is empty on main (#1419).

Pruning them is #1419's job, and the topic-docs convention requires graduation of durable outcomes
*before* the prune (`docs/conventions/topic-docs/README.md:482`). A docs-hygiene sweep that deleted
them would skip step 3 and destroy ungraduated decisions. L1 defers to #1419 and deletes none.

### Generated documents are the only clean cache verdicts

Ten files earn `keep-as-derivation-cache`, all with a named regeneration path plus CI enforcement,
which is the drift-control condition the rubric gates the verdict on. Three are repo-level
(`docs/CATALOG.md` via `scripts/generate-catalog.mjs`; `docs/SKILL-CHEAT-SHEET.md` via
`scripts/generate-cheatsheet.mjs`; `docs/NATIVE-SURFACES.md` via
`plugins/claude-ops/skills/audit-native-overlap/scripts/overlap.py generate`). Seven are the
registered byte-identical cross-plugin copies in `scripts/cross-plugin-source-registry.txt`
(`reference/artifact-protocol.md` x5, `reference/standards-contract.md` x2), each with a dedicated
drift check named in that registry.

### Point-in-time snapshots split cleanly on drift control

Three documents are dated snapshots of things outside the repo. Two keep, one converts, and the
discriminator is exactly the rubric's drift-control gate:

- `docs/hook-migration-audit.md:5` states its own decay rule ("a row is only true as of the stamp
  below") and the audit date. Recorded recheck trigger present. `keep-owns-facts`.
- `docs/extensibility-contract-smoke-tests.md:6` pins the platform version and says "Re-verify fresh
  before relying on a result". Recheck trigger present. `keep-owns-facts`.
- `plugins/claude-ops/skills/known-issues/context/issue-templates.md` has neither, and its consumer
  is instructed never to trust it. `convert-to-pointer`.

### Empty and near-empty T1 files are recorded decisions

`AGENTS.md` (0 bytes) and `CLAUDE.md` (11 bytes) are `keep-owns-facts`, not defects. `git log -1 --
AGENTS.md` is commit `6763cf77`, whose body states: "The file is blanked rather than deleted to
preserve the slot (`CLAUDE.md`'s `@AGENTS.md` import stays)." That is the rubric's worked example
for an empty file whose emptiness is itself a decision.

### Functional artifacts are 11% of the corpus

141 files receive no verdict because they are inputs a component consumes rather than prose a reader
learns from: `**/evals/fixtures/**`, `**/scripts|tests/fixtures/**`, `**/templates/**` (checklists
skills instruct agents to copy and tick), the five `plugins/source-control/skills/*/.claude/*.md`
config fixtures, `.claude/source-control.md`, `.github/pull_request_template.md`, and
`plugins/firecrawl/skills/update/UPSTREAM.md` (machine-written sync state, header: "do not edit by
hand. Written by the skill's scripts/update.sh --apply").

## Cross-lane observations

- **L2-progressive-disclosure.** Two sub-docs are unreachable from their own `SKILL.md` and hold
  unique content, so the fix is to wire them, not to delete them:
  `plugins/implementation/skills/implement/context/gotchas.md` (SKILL.md's routing table at lines
  43-45 cites `feature.md`, `bugfix.md`, `refactor.md`, never `gotchas.md`) and
  `plugins/songwriting/skills/suno/reference/suno-drift-audit-ledger.md` (self-declared "Committed
  authority", cited only from `CHANGELOG.md`).
- **L5-noise.** `plugins/machine-health/skills/audit/README.md:8-25` is a hand-maintained ASCII
  directory tree, derivable by `ls -R` and high-drift; the rest of the file owns real architecture
  rationale, so the file stays and the tree is a trim candidate.
- **L3-ssot.** `plugins/repo-hygiene/skills/clean/context/preflight.md:24-26` restates verbatim the
  output contract already in the header comment of
  `plugins/repo-hygiene/skills/clean/scripts/preflight.sh:4-7`.
- **L5-noise.** `plugins/repo-fleet-hygiene/skills/audit/reference/security-review.md:3-8` carries a
  paragraph that its own next paragraph marks "Superseded by the 2026-08-14 re-check below".

## Method and coverage

Read-only throughout; no source file was edited, moved, or deleted, and no git operation was run.

Every file in the manifest was classified. Classification combined per-file reads with mechanical
detectors over the whole corpus, so that "keep" is an evidenced default rather than an unexamined
one:

1. Index-restatement detector (share of non-blank lines naming a repo file) over all 1302 files.
2. Pointer-shape detector (documents under 4 KB whose lines are 40%+ links) plus an inbound-citation
   count for each hit.
3. Orphan detector: every `reference/`, `references/`, `context/`, `actions/` sub-doc checked for any
   inbound mention across all tracked markdown, shell, Python, and JSON, excluding CHANGELOGs.
4. Self-declared-staleness grep ("superseded", "no longer", "tombstone", "point-in-time", "snapshot,
   not") over the first 14 lines of every file.
5. Doc-restates-script detector: every sub-doc with a same-stem sibling script, read against that
   script's header.
6. Generated-document grep ("never hand-edit", "generated from", "regenerate").
7. Directory-tree-fence grep.
8. Per-slice `git log` and phase-marker extraction across all of `docs/topics/**`.

The orphan detector (3) independently reproduced a finding already recorded in
`docs/topics/context-engineering-claude-5/design/article-sections.md:25`, which names
`ai-briefing/skills/generate/context/execution-flow.md` "genuinely dead — the string occurs nowhere
in the repo". Two contexts converging on the same file is the strongest evidence in this findings
set.
