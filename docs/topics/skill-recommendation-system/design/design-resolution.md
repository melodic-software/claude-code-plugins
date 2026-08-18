---
outcome: early-exit
tier: B
date: 2026-08-18
---

# Design resolution

**Tier B — light design.** The work adds one skill to an existing plugin and extracts one shared
reference doc consumed by three sibling skills inside that same plugin. Tier A signals were checked
and do **not** fire: no new package, no cross-plugin contract, no data-model change. The one
cross-plugin interaction — resolving the candidate catalog via `/claude-ops:inventory` — is an
**optional namespaced skill invocation**, which `docs/PLUGIN-PHILOSOPHY.md` names as a documented
public seam rather than a boundary breach. Intra-plugin shared references are an established pattern
here: `save-point.md` (handoff + continue-in-background), `topic-docs.md`, `observer.md`.

**Resolution: early exit — the design threads were resolved upstream and are recorded below, not
re-derived.** A separate `/planning:design` pass would re-open axes that three independent
adversarial validators, an exploration pass, external research, and a fresh-eyes verifier already
closed against evidence. Provenance for each thread is cited so a reviewer can audit the claim
rather than trust it.

## Resolved design threads

| Thread | Resolution | Resolved by |
|---|---|---|
| Candidate-source contract | Completeness ladder: `/claude-ops:inventory` → operator-supplied catalog via documented seam → in-context listing **with truncation stated in output**. Never the listing alone. | Validators A/B/C converged; the conflict between "walk the plugin cache" (A) and "the repo refuses cache-walking" (B, citing `skill-quality:check`) resolved by reusing the skill that already owns fleet enumeration |
| Output contract | Two tiers — ranked shortlist (≤5/bucket, three-part treatment) + counted complete remainder as bare names; one word expands | Validator C's measurement: the one-tier form is 139 options / 275 lines / ~4,100 tokens |
| No-gatekeeping contract shape | Split into two rules (never omit a name; never let already-done/unnecessary affect rank or omission) plus an explicit never-invent rule | B found the asymmetry (forbids omitting, permits inventing); precedent to cite is `reference/structure.md:33-38` |
| Bucket taxonomy | Now / Next / Skipped-upstream (artifact-grounded) / Spotlight (3, least-recently-surfaced) | C: "Standing" held 60 options (43%); "Backfill" was definitionally all upstream stages, 27 → 2 when artifact-grounded |
| Invocation posture | V1 `disable-model-invocation: true` | A and B independently; zero listing budget, no trigger collision, matches the `ask-matt` precedent |
| Durable-state probe | Extract `plugins/session-flow/reference/gather.md`; three consumers cite it | `point-dont-copy` pins the duplication threshold at two, and `orient` + `workflow` are already two |
| Signal priority | Durable state primary, conversation secondary | C: conversation is least durable, and the compacted session is when the skill is most needed |
| Rotation signal | A ledger this skill writes itself | Decouples the learning mechanism from undocumented `~/.claude.json` internals, keeping Q4 genuinely deferrable |
| Native-first gate | PASS — no native mechanism covers "which installed skill should I run now" | `code.claude.com/docs/en/plugin-relevance.md` fetched 2026-08-18: covers marketplace **install** suggestions from session signals, not skill routing |

## Rung-1 contract, resolved by the Phase 1 probe (2026-08-18)

Mechanism: `plugins/claude-ops/skills/inventory/scripts/inventory.py --disk-only`. Probe capture and
its environmental caveat: `.work/skill-recommendation-system/inventory-capture.md`.

**Result: rung 1 supplies complete skill NAMES (including `disable-model-invocation: true` skills —
`education:teach` verified present) but NO descriptions and NO `metadata.workflow-stage`.** The
ladder therefore resolves two distinct needs rather than one:

- **Name completeness** → inventory; else the in-repo `plugins/**/SKILL.md` tree inside a marketplace
  repo; else the in-context listing with its truncation stated (`liveness-assertion`).
- **Description / stage enrichment** → frontmatter read where files are reachable; else the listing's
  surviving descriptions; else absent.

**Absent enrichment means tier 2, never omission** — the two-tier output shape absorbs the gap by
construction, because tier 1 requires a description and tier 2 is bare names with a count. This is
the design holding up under a real probe rather than needing a patch.

## Contract sketch

**`reference/gather.md`** — shared durable-state probe. Consumers: `orient` (full), `workflow`
(subset), `show-options` (subset). Contract: named probe blocks each consumer cites by name; paths
resolve through the topic-docs binding, never hardcoded; preserves the `#1687` no-precompute
rationale (`$`-expansion fails in worktree-isolated agents); every probe treats failure as an
unknown value and continues.

**`show-options` output contract** — four buckets, each rendering tier 1 (≤5 ranked, three-part
treatment) and tier 2 (remainder, bare invocation names, explicit count). Annotations carry model
judgment; omission never does.

## Deferred by tag, not by silence

`Q4` (usage-metrics surfacing) and `Q11` (execute-after-pick) remain **USER-RESERVED** in the Brief.
`Q12` (`workflow-stage` value) carries arbiter `/planning:plan` and is resolved in the plan body.
