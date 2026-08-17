# /planning:interview Checklist — pocock-shipping-breakdown

Topic: break Matt Pocock's 11-video "Shipping" course section into lanes and decide which
plugin components to add or update. Mode: `me`-leaning relentless rounds.

## Steps

- [x] Step 1: Survey — read docs/upstream/mattpocock-skills.md (SSOT), docs/upstream/mattpocock-skills-v12-map.md, work-items:decompose SKILL.md, tracker-seam CONTRACT.md (github/jira/local-markdown adapters; claim/lease verbs), docs/conventions/standards/README.md; Explore agent sweeping planning/review/implementation surfaces
- [ ] Step 1.5: Auto-detect — SKIPPED (user asked for /interview; many contested decisions → Q&A)
- [x] Step 2: Frontier-rounds loop — 3 rounds, Q1–Q18, two background fact agents
- [x] Step 3: Stop condition — register gate clean (18 registered, 0 open, 1 deferred), user confirmed round 3
- [x] Step 4: PLAN.md Brief written (docs/topics/pocock-shipping-breakdown/PLAN.md); brief cross-check clean
- [x] Step 5: Hand off — breakdown approved and PUBLISHED 2026-08-17 via GitHub MCP (no gh in cloud session; seam bypass recorded as finding on #2942). Container #2933 (work-map, needs-human) carries the Brief; 19 sub-issues natively linked: A=#2934 B=#2935 C=#2936 D=#2937 F=#2938 W=#2939 X=#2940 binding=#2941 hygiene=#2942 lease=#2943 local-md=#2944 topology=#2945 linear=#2946 provenance=#2947 Y=#2948 E=#2949 onboarding=#2950 jira-write=#2951 gitea=#2952. Blocked-by edges in body text (native edges backfill from a gh session): 2949←2934, 2950←2942, 2951←2945, 2952←2950. Course SSOT skeleton created at docs/upstream/aihero-shipping-course.md.

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
- Q9 | answered | round 2 | Canonical naming | work item stays canonical; ticket/issue documented first-class synonyms with trigger coverage
- Q10 | answered | round 2 | Binding-config scrutiny | YES own needs-human lane item, seeded with F1.x/F3.8 findings; format/location decided there
- Q11 | answered | round 2 | Skill granularity | keep supersets; ADD principle: his implement's value = zero-assembly working default chain — scrutiny lane checks ours composes out-of-the-box AND every link configurable, never hard-coded; good defaults + consumer override
- Q12 | answered | round 2 | Provider adapters | order accepted with AMENDMENT: Linear = FULL verb parity with github adapter (read+write+claim/lease+sub-items+edges+frontier), measured by conformance suite; GitHub is reference impl only, not priority
- Q13 | answered | round 2 | Dogfood mechanics | YES — hand-publish Brief as container issue, lane items as native sub-issues
- Probe R2 | answered | round 2 | Day-job SaaS | NOT blocked; Linear fine for personal/agent use (not team-shared); MCP-auth uncertainty noted; not top priority — Linear priority order stands

Facts landed (2026-08-17): Agent A report → upstream-bringover-audit.md (23 candidates C1-C23, upstream delta PRs #878/#880/#848/#879, worse-than-us list); Agent B report → seam-scrutiny-findings.md (binding options a-d, adapter-model trade-offs, adversarial findings F1.1-F1.7 + F3.1-F3.9).

- Q14 | answered | round 3 | Adapter shipping model | HYBRID accepted with caution: deterministic parts scripted per /discipline:script-the-deterministic-work, reasoning stays outside scripts; gated on version handshake (F3.6) + normalization-fidelity check
- Q15 | answered | round 3 | Candidate disposition | per-lane adjudication during lane implementation; worse-than-us list excluded by default; SSOT updated per verdict
- Q16 | answered | round 3 | Seam findings as issues | YES — 4 grouped issues (binding config; contract hygiene; lease hardening; local-markdown honesty); topology findings fold into topology investigation item
- Q17 | answered | round 3 | Lanes W + X | YES both; X likely most agent-ready
- Q18 | deferred | round 3 | Macro/micro lifecycle orchestrator: name, skill, organization, grouping (macro = discovery→pre-planning→planning→implementation→testing→review across a spec; micro = same phases within each ticket; quality-gate + e2e verification before the single PR at the end; his flow repeats review inside tickets, PR at end) | → own needs-human lane item; arbiter: USER-RESERVED (naming + grouping change consumer-facing surface)

Round-3 close: user confirmed shared understanding ("We're completely in line... plan is solid, and we're building") — confirmation gate PASSED. Frontier empty except Q18 (explicitly deferred to lane item).

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
