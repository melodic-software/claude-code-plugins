# mattpocock/skills shipping-flow audit — bring-over candidates (agent A)

Clone: `/workspace/mattpocock/skills`, HEAD `068b6e0c62393147daf03530149cdce209c93da8`; package.json version 1.2.3 (same as our last audited release; everything since `84fdeff` is unreleased main, four pending changesets). Produced 2026-08-17 for the pocock-shipping-breakdown interview. Facts and candidates only — adoption verdicts happen per lane.

## 1. Upstream delta since 84fdeff (v1.2.3)

17 commits, 4 merged PRs, ~64 insertions / 30 deletions. **No new skills, no renames, no new reference files.** All buckets identical to the v1.2.3 inventory in `docs/upstream/mattpocock-skills-v12-map.md`.

- **PR #878 — "call the Skill tool" invocation terminology** (`.changeset/skill-tool-invocation-terminology.md`). Cross-skill invocation rewritten from prose (`run the /grilling skill`) to an explicit tool instruction (`Call the Skill tool with "grilling"`) — bare `/name` prose does not reliably load the target skill ("the documented rough edge behind grill-with-docs's most-reported problem"). A step needing two skills is now **two calls**, never one call with two names. Convention: `.agents/invocation.md:16-22`. Touched: code-review, grill-with-docs, grill-me, improve-codebase-architecture, tdd (SKILL.md:26), to-spec, to-tickets, triage (SKILL.md:76), wayfinder (SKILL.md:77-79,111,115,124), grilling, handoff, claude-handoff, setup-ts-deep-modules.
- **PR #880 — user-invoked-skill invocation fix** (fixes upstream #453). PR #878 had turned five preconditions into literal Skill-tool calls against a **user-invoked** skill, which no skill can ever reach. Fixes: `to-spec:9`, `to-tickets:11`, `triage:43`, `code-review:13`, `wayfinder:25` now read "If not, **tell the user to run** `/setup-matt-pocock-skills`" (human-relay phrasing). `diagnosing-bugs` **Phase 6 post-mortem removed outright** (SKILL.md:130-138) — "it rarely fired in practice." Carve-out added to `.agents/invocation.md`: the Skill-tool convention applies only to model-invoked targets; user-invoked preconditions must be phrased as instructions for the human.
- **PR #848** — domain-modeling trigger reword: triggers on concrete artifacts ("discussing codebase terminology, writing or editing a CONTEXT.md, or recording or editing an ADR").
- **PR #879** — grilling em-dash removal; punctuation only.

Unchanged since 84fdeff: implement, ask-matt (both files), setup-matt-pocock-skills, triage/AGENT-BRIEF.md, triage/OUT-OF-SCOPE.md, tdd/tests.md, tdd/mocking.md.

**SSOT tracked-trigger implications**: (1) the SSOT `diagnosing-bugs` row's trigger ("a release whose changeset names diagnosing-bugs") FIRES on the next upstream release — and the change is a *removal* (the post-mortem handoff). (2) The tracked **Invocation-reach invariant** strand hasn't literally fired, but upstream found six live violations in their own repo (#453 → PR #880) — strong evidence the defect class is real, plus a canonical fix phrasing.

## 2. Candidates (mechanisms he has that we lack or do differently)

### to-spec → Lane A (vs planning:prd/plan)

- **C1. No-interview pure-synthesis spec mode.** `to-spec:7`: "Do NOT interview the user — just synthesize what you already know." Anti-re-interrogation posture for when grilling already happened. Would land as an explicit synthesis-only entry path in planning:prd/plan. SSOT: no verdict (CONVERGENT, not ported, not rejected).
- **C2. Seam-sketch-before-spec + fewest-seams doctrine.** `to-spec:15-17`: sketch test seams before writing the spec; prefer existing seams; "the ideal number is one"; confirm seams with the user. Test topology becomes a spec-time decision. Would land in planning:plan test-strategy and/or tdd:principles / testing:plan. SSOT: flagged as delta, undecided.
- **C3. Spec template sections.** `to-spec:21-75`: Problem Statement / Solution (both user-perspective) / numbered User Stories / **Implementation Decisions** (decisions-made list, not a design doc) / **Testing Decisions** (incl. prior-art test pointers in this codebase) / Out of Scope / Further Notes. Distinctive vs our PRD/plan: Testing Decisions as first-class spec section with prior-art pointers; implementation content framed as decisions-made. SSOT: no verdict.
- **C4. Spec published to the tracker, born ready-for-agent.** `to-spec:19`. Our specs live in topic-docs; only decomposed slices reach the tracker. Spec-as-tracker-item is the delta. NOTE (from §3): he has NO approval gate on this publish — do not import that part. SSOT: no verdict.
- Parity: his no-file-paths-with-prototype-snippet-exception (`to-spec:55-57`) already in decompose SKILL.md:155.

### to-tickets → Lane B (vs work-items:decompose)

- **C5. Prefactor look-ahead at decomposition time.** `to-tickets:23`: "Look for opportunities to prefactor… 'Make the change easy, then make the easy change'"; `to-tickets:34`: prefactoring done first (prefactor tickets become blockers). Our decompose has no prefactoring step; Tidy-First quote lives only in implement's commit discipline. Lands in decompose Step 2. SSOT: to-tickets row = Influence (vocabulary) only.
- **C6. Context-window slice sizing.** `to-tickets:33`: "Each slice is sized to fit in a single fresh context window" — concrete calibration bar. Ours: "prefer many thin slices" + S/M/L, no window-sized rule. One-line candidate for decompose vertical-slice rules. SSOT: no verdict.
- **C7. Integration-branch fallback for wide refactors.** `to-tickets:40` tail: when expand-contract batches can't land green alone, share an integration branch all blocking a final integrate-and-verify ticket — "green is promised only there." Our 2b has the coordinated-window caveat only. SSOT: no verdict.
- **C8. "Work the frontier" phrase.** `to-tickets:65`: compact phrasing for the report step ("any ticket whose blockers are all done; for a linear chain that means top to bottom"). Mechanics = our list-frontier; wording candidate for decompose Step 5. SSOT: no verdict.

### implement → Lane C

Nothing to bring: his implement is 5 lines; ours is a superset on every axis. Adjacent: ask-matt's "/clear context between each ticket — each ticket is self-contained" (`ask-matt:23`) is parity with our phase-boundary ritual.

### tdd → Lane C (vs tdd:principles, testing:write)

- **C9. Pre-agreed-seam gate.** `tdd:22-24`: "Before writing any test, write down the seams under test and confirm them with the user. No test is written at an unconfirmed seam." + canned question: "What's the public interface, and which seams should we test?" Hard consent gate on test topology our implement/tdd chain doesn't state. SSOT: named as un-shipped "tdd top-up"; no rejection.
- **C10. Tautological-test anti-pattern.** `tdd:31` + `tests.md:63-77`: assertion recomputes the expected value the way the code does — "passes by construction and can never disagree with the code. Expected values must come from an independent source of truth — a known-good literal, a worked example, the spec." Our implement has the adjacent anti-gaming line (different failure direction: gaming vs vacuous test). Candidate for tdd:principles / testing:write and the review code lens. SSOT: no verdict.
- **C11. SDK-style mockable boundary interfaces.** `mocking.md:37-59`: at system boundaries prefer per-operation SDK-style functions over one generic fetcher — each mock returns one shape, no conditional logic in test setup. Small design-for-mockability rule for tdd:principles. SSOT: no verdict.

### code-review → Lane D (vs review:quality-gate, review:fanout)

- **C12. Spec axis as a first-class review lens.** `code-review:6-11,66-72`: dedicated Spec sub-agent reporting (a) missing/partial requirements, (b) unrequested behavior = scope creep, (c) implemented-but-wrong — **quoting the spec line for each finding**. Our quality-gate has 8 modes but no spec-fidelity mode; "what was the goal" is a gather input, not a lens. Lands as a `spec` mode in quality-gate or paired lens in fanout. SSOT: "Omitted", not rejected-with-reasons.
- **C13. Never-merge-never-rerank two-axis doctrine.** `code-review:74-87`: present axes separately; "Don't pick a single winner across axes — that's the reranking the separation exists to prevent"; rationale table. Aggregation rule if C12 lands; potentially for fanout's ranking. SSOT: no verdict.
- **C14. Spec-source discovery ladder.** `code-review:27-32`: issue refs in commit messages (`#123`, `Closes #45`) → user-passed path → spec file under docs//specs//.scratch/ matching branch name → ask → skip-with-note. Our quality-gate infers the goal from conversation only. SSOT: no verdict.
- **C15. Fail-fast preflight before spawning reviewers.** `code-review:23`: confirm the ref resolves and the diff is non-empty — "A bad ref or empty diff should fail here — not inside two parallel sub-agents." Cheap guard for fanout/quality-gate shared inputs. SSOT: no verdict.
- **C16. Baseline-suppression rules.** `code-review:38-41`: "The repo overrides" (documented repo standard suppresses the conflicting baseline smell) and "skip anything tooling already enforces." Verify whether our code-reviewer's Fowler baseline carries both suppression rules. SSOT: PR-#464 row covers baseline content only.

### triage → Lane B/D adjacency (vs work-items:triage)

Ours is a superset on nearly everything (AI disclaimer, verify-the-claim, needs-info template, authorAssociation filter, already-implemented check, rejected-concept ledger — `.out-of-scope/` REJECTED as already-adopted; do not re-propose). Remaining:

- **C17. PR-variant agent brief.** `AGENT-BRIEF.md:148-183`: for a PR, "Current behavior" describes the state of the *diff*; the brief specifies what's left to do **to the existing code** rather than build-from-scratch — with worked example. Check whether our reference/agent-brief.md covers PR-shaped briefs; candidate if not. SSOT: no verdict on this variant.

### wayfinder → new small lane W (vs planning:wayfind)

- **C18. "Refer by name" narration rule.** `wayfinder:15-17`: in everything the human reads, refer to tickets by title, never bare ids — "A wall of `#42, #43, #44` is illegible… a name wraps its link." No equivalent in our wayfind; could generalize to all work-items narration. SSOT: not mentioned in the wayfinder row.
- **C19. Out-of-scope map section semantics.** `wayfinder:95-101`: "Scope, not sharpness, lands it here"; out-of-scope fog never graduates; a mis-scoped *existing* ticket gets closed + one line in Out of scope linking it, and stays out of Decisions-so-far. Our wayfind has a Not-yet-specified analog but no visible out-of-scope ledger with these graduation/close rules. SSOT: no verdict on this element.
- **C20. Map-as-index doctrine.** `wayfinder:23`: "a decision lives in exactly one place — its ticket — so the map never restates it, only gists it and links." Likely parity with our tracker-native map; verify rather than assume. SSOT: not adjudicated as a named element.

### Cross-cutting (new since 84fdeff) → authoring-doctrine lane

- **C21. One-skill-per-call phrasing rule.** `.agents/invocation.md` (post-#878): "The Skill tool takes one skill per call. A step that needs two skills is two calls, not one call with two names." We have parity on the main convention; the two-skills-two-calls clarification is a cheap authoring-doctrine line for playbooks:skill-authoring / skill-quality:check. SSOT: not covered.
- **C22. User-invoked-target lint + human-relay phrasing.** PR #880's fix pattern — audit for skills instructing Skill-tool invocation of a user-invocable-only target; canonical rewording "tell the user to run /X". This is the second trigger condition of the SSOT's tracked Invocation-reach invariant — upstream just demonstrated the defect class with six call sites in their own repo. Lands as a skill-quality:check / claude-config:audit-instructions check. SSOT: TRACKED (not rejected); strongest event yet toward its trigger.
- **C23. Domain-modeling trigger phrasing.** Concrete-artifact triggers; possibly relevant to domain-driven-design:curate-language trigger phrasing. Minor. SSOT: no verdict on trigger phrasing.

Note: no "archive-your-specs" wording exists upstream in the skills repo (grep returns nothing); nearest is `.scratch/<feature-slug>/spec.md` persistence in `issue-tracker-local.md:8` and ask-matt's "the last ticket's context is disposable." The archive doctrine lives in the course only.

## 3. Things he does worse (don't cargo-cult)

1. **implement is an empty shell** (5 lines): no divergence detection, no preflight, no phase-boundary durability, no scope-fence, no anti-gaming guardrails.
2. **No untrusted-content boundary in triage/tickets**: reads issue bodies/comments/PR diffs (and checks out + runs external PR code, `triage:74`) with zero prompt-injection posture. Never import his tracker-read flows without our item-content-trust binding.
3. **Folklore numbers as load-bearing figures**: smart zone ~150k (SSOT already rejected); wayfinder tickets "sized to one 100K token agent session" (`wayfinder:57`).
4. **Bloat-inviting spec instruction**: "A LONG, numbered list… extremely extensive" (`to-spec:33,41`) — no calibration by scale. If C3 lands, land the sections, not the LONG directive.
5. **"Refactoring is not part of the loop"** (`tdd:38`): cuts red-green-refactor's third step, batches structural cleanup to review. Ours keeps refactor in-loop with commit-before-simplify save points.
6. **Sub-agent findings presented unverified** (`code-review:76` "verbatim or lightly cleaned") + arbitrary 400-word caps, no severity vocabulary. Our quality-gate mandates re-verifying delegated findings against the diff.
7. **research/<name> throwaway branches** — SSOT already rejected.
8. **No approval gate on to-spec publish** — spec goes straight to the tracker labeled ready-for-agent; only the seams get confirmed. Contrast to-tickets, which gates.
9. **Setup-by-interview writing docs/agents/* + CLAUDE.md edits** — SSOT already rejected; the delta doesn't change the calculus.
10. **Absolutist "no file paths ever" in briefs** (`AGENT-BRIEF.md:16-17`); ours is more nuanced (prototype-snippet exception, provenance backfill).
11. **Windows-hostile AGENTS.md → CLAUDE.md symlink** — already noted in the v12 map; unchanged.
