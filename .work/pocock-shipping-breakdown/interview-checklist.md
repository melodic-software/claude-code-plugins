# /planning:interview Checklist — pocock-shipping-breakdown

Topic: break Matt Pocock's 11-video "Shipping" course section into lanes and decide which
plugin components to add or update. Mode: `me`-leaning relentless rounds.

## Steps

- [x] Step 1: Survey — read docs/upstream/mattpocock-skills.md (SSOT), docs/upstream/mattpocock-skills-v12-map.md, work-items:decompose SKILL.md, tracker-seam CONTRACT.md (github/jira/local-markdown adapters; claim/lease verbs), docs/conventions/standards/README.md; Explore agent sweeping planning/review/implementation surfaces
- [ ] Step 1.5: Auto-detect — SKIPPED (user asked for /interview; many contested decisions → Q&A)
- [ ] Step 2: Frontier-rounds loop
- [ ] Step 3: Stop condition + register gate + user confirmation
- [ ] Step 4: Persist PLAN.md Brief (engineering session) — docs/topics/pocock-shipping-breakdown/PLAN.md
- [ ] Step 5: Hand off (likely: /work-items:decompose to publish issues per lane)

## Session-shorthand glossary

- **lane** — one independently decidable/shippable strand of work absorbed from the course section (may become one or more tracker issues)
- **seam** — the work-item-tracker provider-neutral CLI (github/jira/local-markdown adapters)
- **spec** (Pocock sense) — destination handoff artifact for multi-session work, published to the tracker
- **Brief** — our PLAN.md `## Brief` contract section (nearest in-house analog to his spec)

## Survey facts (settled, not asked)

- Tracker seam: github (full verbs incl. claim/lease/reclaim), local-markdown (offline, no reclaim), jira (READ-ONLY — write verbs exit 6). Binding: tracked `.work-item-tracker.json`, one provider per repo; consumer-local adapter override supported.
- `decompose` = /to-tickets superset (vertical slices, native --blocked-by edges, HITL/AFK, investigation tickets, expand-contract, born-triaged). Uses --blocked-by but NOT --parent containers.
- No spec-on-tracker concept anywhere: plan/PRD live in topic-docs contract slice, pruned at PR close-out (PLAN pasted into PR body); decomposed items carry only a "Source: PLAN Phase N" provenance line.
- Standards convention 1.0.0: relocatable index, SRP files, 3 additive layers, shared plan-time/review-time — already answers his flat CODING_STANDARDS.md.
- Review: quality-gate self mode HAS spec-conformance vs PLAN.md; CI code-review lane has NO originating-issue axis; no whole-container close-out review exists.
- implementation:implement(-dispatch): input = approved PLAN.md; fresh-context phase-verifier for acceptance criteria; work-items:work chains INTO it; PR per item via orchestrator.
- draft-goal-condition: router-first, routes away from /goal; no decompose route-away row; "splitting a goal into sequential per-phase goals" explicitly out of scope.
- Upstream SSOT (docs/upstream/mattpocock-skills.md): setup-matt-pocock-skills + ask-matt already REJECTED with reasons; v1.2.3 audited.

## Open-question register

- Q1 | answered | round 1 | Deliverable shape | Brief → decompose → issues on this repo; DOGFOOD his workflow: one session, one PR, clear/handoff between lanes
- Q2 | answered | round 1 | Lane inventory | accepted, A headline; ADD scrutiny posture lane (existing state not presumed correct; verifier agents over existing surfaces) + mapping-doc accuracy update
- Q3 | answered | round 1 | Spec-on-tracker | YES — extend decompose + plan close-out (not a new to-spec skill); final shape still subject to scrutiny-lane findings; hard-coded conventions must become consumer-configurable
- Q4 | answered | round 1 | Cross-tracker flow | own investigation item + separate per-provider adapter tickets; Linear likely first (user's personal dogfood target; day job has no GitHub); GitHub PR/issue shared-numbering concern recorded
- Q5 | answered | round 1 | Review deltas | YES both (originating-item axis + container close-out review), one lane item
- Q6 | answered | round 1 | Rerouting home | absorb into decompose as re-decompose flow
- Q7 | answered | round 1 | /goal route-away | YES, one Step 0 router row
- Q8 | answered | round 1 | Provenance home | new docs/upstream/aihero-shipping-course.md + fix existing map where stale/inaccurate
- Q9 | open | round 2 | Canonical naming: work item vs ticket |
- Q10 | open | round 2 | Binding-config scrutiny: own lane item? |
- Q11 | answered | round 2 | Skill granularity | keep supersets; ADD principle: his implement's value = zero-assembly working default chain — scrutiny lane checks ours composes out-of-the-box AND every link configurable, never hard-coded; good defaults + consumer override
- Q12 | answered | round 2 | Provider adapters | order accepted with AMENDMENT: Linear = FULL verb parity with github adapter (read+write+claim/lease+sub-items+edges+frontier), measured by conformance suite; GitHub is reference impl only, not priority
- Q13 | open | round 2 | Dogfood mechanics: hand-publish spec container this session |
- Probe R2 | open | round 2 | Day-job constraint: does org block external SaaS (flips Linear → self-hosted Gitea/Forgejo)? |

Facts landed (2026-08-17): Agent A report → upstream-bringover-audit.md (23 candidates C1-C23, upstream delta PRs #878/#880/#848/#879, worse-than-us list); Agent B report → seam-scrutiny-findings.md (binding options a-d, adapter-model trade-offs, adversarial findings F1.1-F1.7 + F3.1-F3.9).

- Q14 | open | round 3 | Adapter shipping model: bundled / generated / hybrid |
- Q15 | open | round 3 | Bring-over candidate disposition strategy (C1-C23) |
- Q16 | open | round 3 | File seam-scrutiny findings as their own issues? |
- Q17 | open | round 3 | Add lanes W (wayfind deltas) + X (authoring doctrine / invocation audit)? |

## Decision tree (`me` mode)

- [ ] Deliverable shape (Q1)
- [ ] Lane inventory locked (Q2)
- [ ] Lane A: spec lifecycle — spec-on-tracker container (Q3); archival doctrine; rerouting (Q6)
- [ ] Lane B: tickets — granularity/estimate calibration; --parent usage (blocked by: Q3)
- [ ] Lane C: execution — TDD wiring delta (round 2)
- [ ] Lane D: review — originating-item axis, close-out review (Q5); standards-capture habit (round 2)
- [ ] Lane F: /goal posture (Q7)
- [ ] Cross-tracker support (Q4)
- [ ] Provenance/bookkeeping home (Q8)
