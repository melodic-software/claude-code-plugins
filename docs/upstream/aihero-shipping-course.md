# Upstream source — AI Hero "Shipping" course section (Matt Pocock)

Single source of truth for everything in this marketplace derived from the **Shipping** section
(11 videos) of Matt Pocock's AI Hero crash course — a distinct upstream source from
[mattpocock/skills](https://github.com/mattpocock/skills), whose SSOT is
[`mattpocock-skills.md`](mattpocock-skills.md). Course content overlaps the skills repo but is
not release-tagged; verdict rows below are the durable record.

**Source basis (re-fetchable):** the course is Matt Pocock's AI Hero crash course, hosted at
<https://www.aihero.dev> (Shipping section, 11 lessons: How to Tackle Massive Tasks; Set Up Your
Issue Tracker; Write Great Specs With This Skill; Split Features Across Context Windows With
Tickets; Executing Your Tickets; Should You Keep Your Specs?; Rerouting; The Goal Command;
Enforcing Your Coding Standards; Ask Matt; Where You Go From Here). Capture method: lesson pages
pasted verbatim by the maintainer into the interview session on 2026-08-17 — course pages are
account-gated and not release-tagged, so the durable cross-check basis is the companion skills
repo pinned at `mattpocock/skills@068b6e0` (the same mechanisms, versioned).

**Audit state:** course section content captured 2026-08-17 (topic `pocock-shipping-breakdown`);
skills repo cross-audited at `main@068b6e0` (post-v1.2.3 unreleased). The two audit reports
(`upstream-bringover-audit.md`, candidates C1–C23; `seam-scrutiny-findings.md`, findings F1.x /
F3.x) are graduated to durable storage as comments on container #2933 — the memory-tier copies
under `.work/` are session-local and uncommitted per the topic-docs contract.

**Recheck trigger:** a mattpocock/skills release whose changeset names `to-spec`, `to-tickets`,
`implement`, `tdd`, `code-review`, `triage`, or `wayfinder` — the course's flow skills. Course
page updates are not observable events; the skills-repo release stream is the proxy.

## Spec container

All absorption work is tracked under the spec container
[melodic-software/claude-code-plugins#2933](https://github.com/melodic-software/claude-code-plugins/issues/2933)
(sub-issues per lane). The container closes — archival by closure — when every lane lands and a
container close-out review against the spec passes.

## Verdict table

One row per lane; verdicts filled in as each lane's sub-issue closes. Statuses: ADOPTED /
PARTIAL / REJECTED / OPEN.

| Lane | Course concept | Candidates | Our surface | Verdict | Item |
|---|---|---|---|---|---|
| A | Spec lifecycle: /to-spec, spec-on-tracker, archive-your-specs | C1–C4 | planning:prd/plan + work-items:decompose | OPEN | #2934 |
| B | /to-tickets deltas | C5–C8, C17 | work-items:decompose | OPEN | #2935 |
| C | /implement + /tdd wiring, zero-assembly chain | C9–C11 | implementation:implement, tdd:principles, testing:write | OPEN | #2936 |
| D | Two-axis review, spec lens, close-out review | C12–C16 | review:quality-gate/fanout | OPEN | #2937 |
| E | Rerouting: tickets disposable, spec editable | — | work-items:decompose (re-decompose flow) | OPEN | #2949 |
| F | /goal vs tickets posture | — | planning:draft-goal-condition | OPEN | #2938 |
| W | Wayfinder deltas | C18–C20 | planning:wayfind | OPEN | #2939 |
| X | Invocation doctrine (skills-repo delta PRs #878/#880) | C21–C23 | playbooks:skill-authoring, skill-quality:check | ADOPTED (C21 ADOPTED, C22 fired-and-resolved with zero Skill-tool violations, C23 ALREADY-PRESENT; standing check considered-and-deferred) | #2940 |
| Y | Macro/micro lifecycle orchestrator (interview Q18) | — | undecided (session-flow / work-items / new) | OPEN | #2948 |

Seam-scrutiny follow-ons (not course-derived, surfaced by the same audit): binding config
(#2941), contract hygiene (#2942), lease hardening (#2943), local-markdown docs (#2944),
multi-provider topology (#2945), Linear adapter (#2946), adapter-onboarding skill (#2950),
Jira write (#2951), Gitea/Forgejo adapter (#2952), provenance/map fixes (#2947).

## Decided at interview (2026-08-17, not per-lane)

- **Naming:** "work item" stays canonical; "ticket"/"issue" are documented first-class synonyms
  (trigger coverage lands via #2947). Rename of plugin/seam REJECTED.
- **Setup-by-interview** (course "Set Up Your Issue Tracker" / `setup-matt-pocock-skills`):
  remains REJECTED per the skills-repo SSOT — this marketplace configures via the tracker-seam
  binding + setup skills.
- **Adapter shipping model:** HYBRID — bundled hardened majors + consumer-side generator skill
  for the tail (#2950), gated on contract-version handshake and normalization-fidelity
  conformance.
- **Excluded by default** (course/skills practices we will not import): approval-gate-free spec
  publish; tracker reads without the item-content-trust boundary; folklore token figures
  (~150k smart zone, 100k ticket sizing); unverified sub-agent review findings;
  refactoring-excluded TDD loop; `research/<name>` branches (previously rejected).

## Cross-links

- Skills-repo SSOT: [`mattpocock-skills.md`](mattpocock-skills.md) (attribution table; tracked
  strands). The invocation-reach tracked strand's audit lands via lane X (#2940).
- Full v1.2 map: [`mattpocock-skills-v12-map.md`](mattpocock-skills-v12-map.md). Staleness
  fixes and absorbed-under-different-name traceability land via #2947.
