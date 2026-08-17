# pocock-shipping-breakdown

## Brief

### TLDR

Absorb the durable ideas from Matt Pocock's 11-video "Shipping" course section (spec → tickets →
implement → review across multiple context windows) into this marketplace as separate, vetted
work items — closing the one confirmed structural gap (no durable, tracker-published destination
artifact for multi-session work) and hardening the surrounding machinery found by adversarial
scrutiny — while converting hard-coded plugin conventions into consumer-configurable seams.

### Goal

The problem: work too large for one context window needs a destination artifact (spec) that is
durable across sessions, branches, machines, and agents, plus a journey decomposition (tickets)
sized to context windows — and our current contract artifacts (PLAN.md/PRD in topic-docs) are
branch-tracked and pruned at merge, so multi-PR multi-machine efforts have no durable
team-visible destination. Secondarily: everything we ship to close that gap must carry good
defaults yet be consumer-configurable (locations, formats, providers, labels, flows), never
hard-coded plugin opinions.

Deliverables of this topic:

1. A spec container item on this repo's tracker carrying this Brief, with all approved lane
   items as native sub-issues (dogfooding the Lane A design before building it).
2. The lane items themselves (see breakdown), each independently workable across future
   sessions, mostly via `/work-items:work`.

### Constraints

- Consumer-configurability doctrine: good defaults, everything overridable; no new fixed
  filenames/locations/labels without a remap seam or a recorded deferral (guiding principle
  locked in round 2, Q11).
- Adjudication of the 23 upstream bring-over candidates (C1–C23,
  `.work/pocock-shipping-breakdown/upstream-bringover-audit.md`) happens per-lane during lane
  implementation; the "worse-than-us" list (same doc §3) is excluded by default — notably: no
  approval-gate-free spec publish, no tracker reads without the item-content-trust boundary, no
  folklore token figures.
- Hybrid adapter model is gated on the contract-version handshake (F3.6) and a
  normalization-fidelity conformance check; deterministic parts scripted
  (/discipline:script-the-deterministic-work), reasoning outside scripts (Q14).
- Provider naming stays "work item" canonical with "ticket"/"issue" as documented first-class
  synonyms (Q9).
- Upstream provenance: course-derived verdicts recorded in a new
  `docs/upstream/aihero-shipping-course.md`; per-candidate verdicts update the mattpocock-skills
  SSOT as lanes close (Q8, Q15).

### Acceptance criteria

- [ ] Spec container item exists on the tracker with this Brief as body, sub-issues linked
      natively (`--parent`), blockers wired (`--blocked-by`), HITL/AFK labels per breakdown.
- [ ] Every approved lane in the breakdown has exactly one tracker item, born triaged.
- [ ] `docs/upstream/aihero-shipping-course.md` exists with lane→verdict skeleton and
      cross-link from `docs/upstream/mattpocock-skills.md`.
- [ ] Execution contract (bulk work): each lane item is worked one at a time in its own
      session/worktree (apply → verify → close), closed only when its own acceptance criteria
      pass; the container closes only after a container close-out review of the whole against
      this Brief (itself dogfooding Lane D's close-out-review concept).

### Captured assumptions

- GitHub remains this repo's coordination provider; the PR/issue shared-numbering concern is
  accepted here (it is the user's day-job repos where it bites) and addressed in the topology
  investigation item.
- The two scrutiny reports in `.work/pocock-shipping-breakdown/` are the evidence base lane
  items cite; they are session artifacts, not contracts.
- Upstream (mattpocock/skills) audited at HEAD `068b6e0` (post-v1.2.3 unreleased main); no new
  skills since v1.2.3 — course content is the only additional source.

### Out-of-scope

- Implementing any lane in this topic/session beyond publishing the items (each lane is its own
  multi-session effort).
- The user's personal day-job Linear/Jira setup (their org tooling; only the adapters/topology
  land here).
- Renaming the `work-items` plugin or seam (Q9 decided: no rename).
- Re-litigating SSOT-rejected upstream items (setup-by-interview, ask-matt router,
  research/<name> branches, `.out-of-scope/` KB, ~150k smart-zone figure).

### Deferred questions

- Q18 — Macro/micro lifecycle orchestrator: what is the name, skill home, and grouping for the
  macro-level workflow (discovery → pre-planning → planning → implementation → testing → review
  spanning a whole spec, with micro-cycles of the same phases inside each ticket, quality-gate +
  e2e verification before the single end PR)? Deferred to its own lane item. Arbiter:
  USER-RESERVED (consumer-facing naming and flow grouping).

## Plan

(Empty — no implementation plan in this topic; each lane item carries its own. The breakdown
below is the decomposition source for `/work-items:decompose`.)

### Lane breakdown (decompose source)

| # | Item | Role | Blocked by |
|---|------|------|-----------|
| 0 | Spec container: Shipping-lifecycle absorption (this Brief) | container, human-gated | — |
| 1 | Lane A: spec-on-tracker lifecycle (publish container w/ spec via decompose + plan close-out; close-at-ship archival; C1–C4) | human-gated | — |
| 2 | Lane B: decompose deltas (C5 prefactor-first, C6 window sizing, C7 integration-branch fallback, C8 frontier phrasing, C17 PR-variant brief check) | agent-ready | — |
| 3 | Lane C: TDD wiring + zero-assembly default-chain check (C9–C11) | human-gated | — |
| 4 | Lane D: review deltas (C12 spec lens, C13 two-axis doctrine, C14 discovery ladder, C15 preflight, C16 suppression rules; container close-out review) | human-gated | — |
| 5 | Lane E: rerouting / re-decompose flow in decompose | agent-ready | 1 |
| 6 | Lane F: /goal route-away row in draft-goal-condition | agent-ready | — |
| 7 | Lane W: wayfind deltas (C18–C20) | agent-ready | — |
| 8 | Lane X: authoring doctrine + invocation-reach audit (C21–C23) | agent-ready | — |
| 9 | Seam: binding config — layering/location/format + climb anchor F1.1 + root regimes F3.8 | human-gated | — |
| 10 | Seam: contract hygiene — dangling ADR 0022, version handshake F3.6, triple-defined defaults F3.7 | agent-ready | — |
| 11 | Seam: lease hardening — mid-flight renew guidance, clock-skew note, TOCTOU wording, ttl-0 doc | agent-ready | — |
| 12 | Seam: local-markdown branch-confinement documentation (F3.4) | agent-ready | — |
| 13 | Investigation: multi-provider topology (source-of-record read + coordination write; F3.1/F3.2/F3.9; issues-only-repo option; PR-numbering) | human-gated (investigation) | — |
| 14 | Linear adapter — full verb parity + conformance binding | human-gated | — |
| 15 | Adapter-onboarding/generator skill (hybrid model tail) | human-gated | 10 |
| 16 | Jira write support (guarded, opt-in) | human-gated | 13 |
| 17 | Gitea/Forgejo adapter (candidate first dogfood of #15) | human-gated | 15 |
| 18 | Provenance: aihero-shipping-course.md + v12-map staleness fixes + synonym trigger coverage (Q9) | agent-ready | — |
| 19 | Lane Y: macro/micro lifecycle orchestrator — name, grouping, skill home (Q18) | human-gated | — |
