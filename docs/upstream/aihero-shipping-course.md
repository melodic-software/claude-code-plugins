# Upstream source — AI Hero "Shipping" course section (Matt Pocock)

## Contents

- [Spec container](#spec-container)
- [Verdict table](#verdict-table)
- [Candidate index (C1–C23)](#candidate-index-c1c23)
- [Lane A (#2934)](#lane-a-2934)
- [Lane B (#2935)](#lane-b-2935)
- [Lane C (#2936)](#lane-c-2936)
- [Lane D (#2937)](#lane-d-2937)
- [Lane W (#2939)](#lane-w-2939)
- [Lane X (#2940)](#lane-x-2940)
- [Lane E (#2949)](#lane-e-2949)
- [Decided at interview (2026-08-17, not per-lane)](#decided-at-interview-2026-08-17-not-per-lane)
- [Adapter-track scope decision (2026-08-20)](#adapter-track-scope-decision-2026-08-20)
- [Cross-links](#cross-links)

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
| A | Spec lifecycle: /to-spec, spec-on-tracker, archive-your-specs | C1–C4 | planning:prd/plan + work-items:decompose | PARTIAL (C4 adopted gate-added; C3 partial; C1 already-present; C2 routed to #2936) | #2934 |
| B | /to-tickets deltas | C5–C8, C17 | work-items:decompose | ADOPTED | #2935 |
| C | /implement + /tdd wiring, zero-assembly chain | C2, C9–C11 | planning:plan, tdd:principles, testing:write | PARTIAL (C2+C9 relocated to planning:plan; C10+C11 already-present; chain doc rejected-with-reasons) | #2936 |
| D | Two-axis review, spec lens, discovery ladder, preflight | C12–C16 | review:quality-gate | PARTIAL (C12+C14 adopted-corrected; C13+C16 already-present; C15 partial) | #2937 |
| E | Rerouting: tickets disposable, spec editable | — | work-items:decompose (re-decompose flow) | ADOPTED | #2949 |
| F | /goal vs tickets posture | — | planning:draft-goal-condition | ADOPTED (sixth route-away row: multi-window work routes to spec + decomposed items; advisory, no folklore token figures) | #2938 |
| W | Wayfinder deltas | C18–C20 | planning:wayfind | PARTIAL (C18+C19 adopted; C20 already-present) | #2939 |
| X | Invocation doctrine (skills-repo delta PRs #878/#880; C23 from #848) | C21–C23 | playbooks:skill-authoring, skill-quality:check | PARTIAL (C21+C22 adopted; C23 already-present — corrected 2026-08-21 from a flat ADOPTED, which disagreed with C23's own disposition and with how every other lane holding an already-present candidate is graded) | #2940 |
| Y | Macro/micro lifecycle orchestrator (interview Q18) | — | work-items:ship | ADOPTED (thin router; PR topology per-container via the `Execution shape:` line, not repo config; item/checkpoint/phase-boundary canonized in `work-items/reference/execution-shape.md`; the glossary deferral has since ENDED — `docs/GLOSSARY.md` landed 2026-08-20 (#3062) and `phase boundary` is promoted there, while `item` and `checkpoint` stay reference-local as seam-specific terms) | #2948 |

Seam-scrutiny follow-ons (not course-derived, surfaced by the same audit): binding config
(#2941), contract hygiene (#2942), lease hardening (#2943), local-markdown docs (#2944),
multi-provider topology (#2945), Linear adapter (#2946), adapter-onboarding skill (#2950),
Jira write (#2951), Gitea/Forgejo adapter (#2952), provenance/map fixes (#2947).

## Candidate index (C1–C23)

Every lane verdict above and below cites a candidate by id. The definitions were originally
drafted into the topic's **memory** slice (`.work/`, self-ignored, never committed) — which meant
each verdict pointed at an artifact that dies with the working tree. They are graduated here, one
line each, so the ids stay resolvable after the topic slice is gone. Upstream line references are
against `mattpocock/skills@068b6e0` (see "Source basis" above) and are a snapshot, not a live
pointer.

| Id | Candidate | Upstream source | Lane |
|---|---|---|---|
| C1 | No-interview pure-synthesis spec mode — "Do NOT interview the user; just synthesize what you already know" | `to-spec:7` | A |
| C2 | Sketch the test seams before writing the spec, prefer existing seams, confirm them with the user ("the ideal number is one" excluded) | `to-spec:15-17` | A → C |
| C3 | Spec template sections, notably **Testing Decisions** as a first-class section with prior-art test pointers, and implementation content framed as decisions-made | `to-spec:21-75` | A |
| C4 | The spec is published to the tracker, born ready-for-agent (upstream has no approval gate on the publish — that part excluded) | `to-spec:19` | A |
| C5 | Prefactor look-ahead at decomposition time; prefactor slices become blockers of what they unblock | `to-tickets:23,34` | B |
| C6 | Each slice sized to fit a single fresh context window | `to-tickets:33` | B |
| C7 | Integration-branch fallback for wide refactors — green is promised only at the final integrate-and-verify item | `to-tickets:40` | B |
| C8 | "Work the frontier" phrasing for the report step | `to-tickets:65` | B |
| C9 | Pre-agreed-seam gate — "No test is written at an unconfirmed seam," plus the canned "what's the public interface, and which seams should we test?" question | `tdd:22-24` | C |
| C10 | Tautological-test anti-pattern — an assertion that recomputes the expected value the way the code does passes by construction; expected values must come from an independent source of truth | `tdd:31`, `tests.md:63-77` | C |
| C11 | SDK-style mockable boundary interfaces — per-operation functions over one generic fetcher, so each mock returns one shape with no conditional logic in test setup | `mocking.md:37-59` | C |
| C12 | Spec axis as a first-class review lens — missing/partial requirements, unrequested behavior, implemented-but-wrong, each finding quoting its spec line | `code-review:6-11,66-72` | D |
| C13 | Never-merge-never-rerank two-axis doctrine — present axes separately, no single winner across axes | `code-review:74-87` | D |
| C14 | Spec-source discovery ladder — issue refs in commits → user-passed path → spec file matching the branch → ask → skip with a note | `code-review:27-32` | D |
| C15 | Fail-fast preflight before spawning reviewers — a bad ref or empty diff fails there, not inside two parallel sub-agents | `code-review:23` | D |
| C16 | Baseline-suppression rules — a documented repo standard overrides the conflicting baseline smell; skip anything tooling already enforces | `code-review:38-41` | D |
| C17 | PR-variant agent brief — "current behavior" describes the state of the diff, and the brief says what is left to do to existing code | `AGENT-BRIEF.md:148-183` | B |
| C18 | "Refer by name" narration — human-facing text names tickets by title, never bare ids | `wayfinder:15-17` | W |
| C19 | Out-of-scope map section semantics — scope not sharpness lands it there; out-of-scope fog never graduates; a wrongly scoped existing ticket is closed with one linking line | `wayfinder:95-101` | W |
| C20 | Map-as-index doctrine — a decision lives in exactly one place, its ticket; the map gists and links, never restates | `wayfinder:23` | W |
| C21 | One-skill-per-call phrasing — a step needing two skills is two calls, not one call naming two | `.agents/invocation.md` (post-#878) | X |
| C22 | User-invoked-target lint plus human-relay phrasing — never Skill-tool-invoke a user-invocable-only target; say "tell the user to run /X" | skills-repo PR #880 | X |
| C23 | Domain-modeling trigger phrasing keyed on concrete artifacts | `domain-modeling/SKILL.md:3` (PR #848) | X |

No "archive-your-specs" wording exists upstream in the skills repo — the nearest is
`.scratch/<feature-slug>/spec.md` persistence in `issue-tracker-local.md:8`. That doctrine lives
in the course only, and is adjudicated in Lane A.

## Lane A (#2934)

Interview rounds 1–4 locked the shape (2026-08-17): extend `work-items:decompose` +
`planning:plan close-out` — NOT a new to-spec skill; mandatory approval gate; opt-in and
consumer-configurable throughout.

- **C1 ALREADY-PRESENT**: no-interview pure-synthesis spec mode. `planning:interview`
  synthesizes directly when intent is clear (anti-re-interrogation is its documented smart
  default), and `planning:plan`'s empty-argument smart default finalizes an existing
  conversation plan without re-interviewing. No new entry path added.
- **C2 PARTIAL**: seam-sketch-before-spec accepted as doctrine direction but ROUTED to lane C
  (#2936), where it lands alongside C9 (the pre-agreed-seam gate — same doctrine family, one
  landing surface across planning:design / tdd:principles / testing:plan). The "ideal number
  of seams is one" numeric absolutism is REJECTED (folklore-figure posture).
- **C3 PARTIAL**: container body = the Brief **verbatim** (our spec template), plus an optional
  `## Testing decisions` section with prior-art test pointers — that section is the adopted
  delta. The "LONG, numbered, extremely extensive" directive stays excluded (worse-than-us
  list).
- **C4 ADOPTED (gate-added variant only)**: the spec publishes to the tracker as a `work-map`
  container with slices as native sub-items (`work-items:decompose` "Container lifecycle") —
  opt-in at approval, `decompose_container_publish` userConfig pre-select, container label
  remappable via binding `config.container_label`. Upstream's gate-free publish remains
  excluded.
- **Archive-your-specs** (course "Should You Keep Your Specs?"): ADOPTED as archival by
  closure — the container closes at ship after a close-out review against its body; a closed
  container stays findable but no spec sits in repo or open tracker for agents to trust over
  code. Pass-by-reference ADOPTED: `/work-items:work` reads the parent container body as
  quoted briefing data before executing a sub-item.

## Lane B (#2935)

- **C5 ADOPTED**: prefactor look-ahead at decompose time ("make the change easy, then make the easy change"); prefactor slices are blockers of the slices they unblock. Qualitative — no token folklore.
- **C6 ADOPTED**: "one fresh context window" granularity bar alongside S/M/L. Qualitative only; folklore token figures remain excluded-by-default.
- **C7 ADOPTED as fallback**: when expand-contract batches cannot land green alone, share an integration branch all blocking a final integrate-and-verify item. Default remains expand → migrate → contract (`decompose` §2b). Those items require a separate integration-branch workflow; `/work-items:work` still targets the default branch.
- **C8 ADOPTED**: "work the frontier" phrasing in the present/report step (unblocked slices first).
- **C17 ADOPTED**: PR-variant brief in `plugins/work-items/reference/agent-brief.md` (current-behavior-of-the-diff, finish-what-exists). Does not replace the bug/feature template.

## Lane C (#2936)

Design locked 2026-08-19 after adversarial validation (two fresh-context validators, rationale
withheld). **All five** initial answers were challenged: two proposed ADOPT verdicts turned out
to be already shipped, one proposed enforcement site structurally cannot host the rule it was
given, and one disposal venue does not exist.

- **C2 + C9 PARTIAL, relocated** — the pre-agreed-boundary discipline lands in
  `plugins/planning/skills/plan/SKILL.md`'s existing **Test strategy** element (the one that
  already invokes `/tdd:principles`) and its template placeholder, in that section's own
  vocabulary: the plan names the public interfaces the tests will drive, each marked existing or
  newly-introduced, and Step 5's approval is what settles them. Two corrections over the course's
  version. (1) **Not phrased as "seams."** `seam` is fleet-registered vocabulary —
  `docs/conventions/seam-phrasing/` owns it for presence-gated cross-plugin references, and
  `architecture:improve` enforces its own sense as controlled vocabulary that explicitly forbids
  substitution; a third sense landing in `planning` would overload a registered term. (2) **Not
  hosted by `implementation:phase-verifier`**, the site originally proposed: that agent grades
  binary acceptance criteria against a final diff and is told to *"Refuse to guess"* its inputs,
  while "boundaries stated *before* the first test" is a temporal-ordering claim no final-diff
  grader can observe — wiring it there manufactures INCONCLUSIVE-and-escalate loops. Upstream's
  hard consent gate ("no test is written at an unconfirmed seam") is therefore **softened
  deliberately**: an unattended run cannot obtain confirmation, so a boundary implementation picks
  that the plan never named becomes a `DEVIATIONS.md` entry reviewed at PR time — this repo's
  existing unattended-assumption mechanism — rather than a blocking stop. The "ideal number of
  seams is one" absolutism stays REJECTED (Lane A's folklore-figure posture).
- **C10 ALREADY-PRESENT (prose)** — the tautological-test anti-pattern is carried at
  `plugins/tdd/skills/principles/reference/anti-patterns-khorikov.md:96,270` and, in checklist
  form, at `plugins/testing/skills/write/context/write.md:78` ("expected values are independently
  sourced … never recomputed the same way the code under test computes them"). No change.
  **Correction to an overstatement made while drafting this lane: the coverage is prose-only, not
  executable.** `testing/audit`'s `cant-fail-scan.sh` concedes in its own header that
  `rule-recomputed-expectation` "detects the decidable core — textually identical sides — not
  every recomputation shape," and a validator ran it over three canonical tautological tests for
  zero findings; the canonical Khorikov shape (compute `expected` with the production algorithm,
  then assert) does not fire. **The review code-lens criterion that closes the executable gap is
  landed** in `plugins/review/agents/code-reviewer.md`'s Code quality checklist (`review` 0.24.0):
  it asks what the expected value's independent source is, names the round-trip/identity case
  alongside the canonical shape, and cedes the textually-identical-sides core to
  `cant-fail-scan.sh` by name so the scanner and the lens cannot double-report. Placement went to
  the agent definition rather than `quality-gate/context/criteria.md` because that file is a
  routing doc — it resolves the project's standards index and carries no criteria of its own,
  which is where its own "Baseline when the ladder yields nothing" step already points.
- **C11 ALREADY-PRESENT + one-clause edit** — `test-doubles.md` has carried
  `## SDK-Style Interfaces Over Generic Fetchers` (the GOOD/BAD pair and "each mock returns one
  specific shape, no conditional logic in test setup") since `85aa8066`, predating the audit that
  proposed it; adding it would have produced a duplicate section. Landed instead: the missing
  **subordination** clause — the shape rule never widens what gets mocked, and "mock only
  unmanaged dependencies" still decides whether a boundary is mocked at all.
- **Zero-assembly chain doc REJECTED with reasons** (not deferred). The proposal was to write the
  default chain canonically into `plugins/implementation/README.md` and convert `implement`'s
  scattered mentions into citations of it. Withdrawn on five defects, the decisive one being that
  the chain as drafted was **factually wrong**: the fresh-context phase verifier fires at *every
  phase boundary* (a loop) while confirm → quality-gate → pull-request fires *once at completion*,
  and that verifier is dispatched by `implementation:implement-dispatch`, not `implement` —
  writing it down canonically would have laundered the error into an SSOT. Also: READMEs are
  human-facing and graded on a different bar by docs hygiene; `PLUGIN-PHILOSOPHY.md:474-476`
  routes a cross-plugin concern to a `docs/conventions/` owner doc rather than a plugin README;
  converting the inline mentions to citations would **strip the presence gates from the invocation
  sites** (a seam-phrasing violation — the gate belongs where the invocation is instructed); and
  only 2 of 7 mentions actually overlap. The acceptance criterion is served as it stands by
  `implement/SKILL.md:186` + `:199` with gates intact. The genuine find — `session-flow`'s
  `pre-pr.md` owning an ordered pre-PR sequence in a **different** order, declared unreorderable —
  **is settled, not deferred.** `pre-pr.md`'s order is doctrine: outcome verification renders on
  the code that ships, and steps 4–6 (simplify, review the simplify diff, re-test) mutate the diff
  between review and verification, so a verdict rendered before them describes code that no longer
  exists at PR time. The competing reading ("confirm it works before spending review effort") is
  already served earlier — by `pre-pr.md` step 1 and by `implement`'s own build check and full test
  pass. Decisive evidence that this was a one-surface correction rather than a coin flip:
  `verification`'s **own** chaining table (`skills/confirm/SKILL.md:125,128`) already fires on
  "review gate passes" → suggest `confirm`, then PR after CONFIRMED. The skill that renders the
  verdict, the skill that lists the sequence, and the plugin that opens the PR all agreed;
  `implement`'s handoff step was the lone dissenter. Landed: a new owner doc
  `docs/conventions/pre-pr-ordering/` with a registry row in `PLUGIN-PHILOSOPHY.md` (the registry's
  own trigger — "a new cross-plugin convention lands in an owner doc before a second plugin adopts
  it" — had already fired); `pre-pr.md` cites the owner for the order and keeps ownership of what
  each step does; its override-boundary paragraph corrected from "fixed plugin identity" to fleet
  identity, since the seam it denied was being exercised by a sibling plugin at the handoff point;
  and `implement/SKILL.md:186` + `:199` rewritten to review → verify → PR with every presence gate
  intact.
- **Issue premise recorded UNVERIFIED, not STALE.** The issue's "`/tdd:principles` exists but
  rarely gets invoked during implementation (known behavioral gap)" was initially judged STALE on
  the grounds that the invocation is already wired at 7 sites. That inverts the claim: wiring is a
  property of text, invocation is runtime behavior, and seven wired sites *plus* rare invocation
  are jointly evidence that wiring is not the lever. Wiring confirmed at 7 sites; the behavioral
  claim stays unmeasured. Measurement routes to the instrument that exists — `claude-ops`'s
  `SkillUse` telemetry hook — and **not** to an evals item: `plugins/evals/README.md:24-26` states
  "No command in this plugin executes model-graded evals," so an evals filing would produce JSON
  no runner executes. Stated limit: that hook records no caller attribution, so an implement→tdd
  co-occurrence reading is a proxy, not proof. **Measured, and the premise stays UNVERIFIED — now
  with an instrument rather than a hand-wave.** `plugins/claude-ops/skills/audit-skill-visibility/
  scripts/skill-pair-cooccurrence.sh` (`claude-ops` 0.35.0) is the repeatable reading; placement
  went to `audit-skill-visibility`, not `observability`, because `observability`'s own
  `context/read-routing.md:32` already assigns interpretation of skill-usage data to
  `audit-skill-visibility` and keeps only the store, the pipeline, and retention. Run against the
  only store reachable from this environment (`.claude/observability/skill-usage.jsonl`,
  17 events, 2026-08-17 → 2026-08-20, a 3-day span): **`implementation:implement` fired zero
  times, so the denominator is empty and the verdict is WITHHELD, not 0%.** An empty denominator
  is a population that was never observed, not a rate of zero — the script refuses that inversion
  by construction and the refusal carries a regression test verified to fail without its guard.
  **The schema-widening question is decided here rather than filed: do not widen the `SkillUse`
  record.** Caller identity is not merely absent from the schema, it is absent from the hook's
  *input* — a PostToolUse payload carries `tool_name`, `tool_input`, and `tool_response`, and
  nothing in it names the invoking skill. Recovering it would mean reading the session transcript,
  which turns a bounded telemetry hook into a conversation reader and crosses the boundary
  `observability/context/privacy.md` guards. The better signal needs no change at all and already
  ships: OTEL's `claude_code.skill_activated` carries `invocation_trigger`, separating `user-slash`
  from `claude-proactive` — which is the axis this premise actually asks about (does the model
  reach for `tdd:principles` unprompted), and `audit_skill_visibility.py` already gates it as
  `T-full`-only.

## Lane D (#2937)

Design locked 2026-08-19 after adversarial validation (two fresh-context validators, rationale
withheld; three of five initial answers revised on evidence).

- **C12 ADOPTED-corrected**: `spec` mode — a 9th `quality-gate` lens judging the diff against its
  originating spec, in `plugins/review/skills/quality-gate/context/spec.md`. That file **owns** the
  finding-class enum (`missing` / `scope-creep` / `wrong`, each finding quoting its spec line);
  `self.md`'s fenced worker checklist keeps a shallow divergence check and does not restate the
  taxonomy, and the pointer to the owning file sits in orchestrator-facing escalation text, not
  inside the subagent template a fresh-context worker cannot act on. **Correction: this lens did
  NOT fill the dangling consumer**, and the sentence that said so was wrong twice over. The
  consumer in `work-items:decompose` and `work-items:ship` was container-scoped, while this lens is
  branch-scoped — `work-items`' own changelog records that the route "landed on nothing
  container-scoped even after `review` 0.22.0 shipped the branch-scoped `spec` lens." It was
  #3027's close-out mode that filled it. Nor do those skills still carry the phrase "the review
  plugin's spec-fidelity machinery": both now name `/review:quality-gate close-out --container
  <container-id>` directly, and the old wording survives only in changelog history.
- **C13 ALREADY-PRESENT + one targeted edit**: the course's two-axis intent is already implemented
  as `fanout`'s two-axis presentation (merged ranked queue plus a per-dimension regrouping). The
  originally proposed "never merge or rerank across axes" rule was **withdrawn** — it would negate
  the normalization pipeline `fanout` exists to run, and its second scope (invocations pairing spec
  with a quality mode) is unimplementable against `quality-gate`'s one-lens-per-invocation rule.
  Landed instead: `self.md`'s parallel-worker split tightened from "merge only after verification"
  to keep-separate presentation, and the **vocabulary recorded once** in
  `plugins/review/context/severity.md` — in this plugin `axis` means severity/confidence; a review
  perspective is a `lens`. Three incompatible senses were live before that note.
- **C14 ADOPTED-corrected**: spec-source discovery ladder in `context/spec.md` — `--spec <path|id>`
  → item refs harvested from branch commits / PR body → the topic's contract slice → ask → skip
  with a note. Corrections over the course's version: (1) the seam's normalized item object has
  **no `body` field**, so spec text comes from the **provider-mechanic read**; (2) a harvested bare
  `#N` is **validated** (strictly numeric; owner/repo to a repo-name shape) and then **promoted** to
  the qualified `<provider>:<owner>/<repo>#<number>` form, with the read scoped by `--repo` to that
  id's own repository — commit and PR text is attacker-influenceable through a fork PR, and a bare
  number would read a same-numbered issue in the *current* repo; (3) the contract-slice rung keys
  on the **topic slug**, not the branch slug — the branch axis is deliberately lossy. **Design
  correction found in PR review:** the item is read through a documented public seam or the provider
  mechanic, never by invoking the sibling plugin's seam CLI — `PLUGIN-PHILOSOPHY.md` forbids
  discovering another plugin's installation directory, and no namespaced item-fetch action exists
  today. So this is *not* the marketplace's first cross-plugin seam call; the provider-mechanic read
  is the operative path, the rung works with no tracker plugin installed, and parent linkage (whose
  authoritative source, `get-item`, is unreachable from here) degrades to best-effort or an explicit
  `--spec`.
  Recorded limit: the contract slice is pruned before merge, so that rung goes empty post-merge and
  recovery is best-effort — which is why the tracker item is the durable spec home.
- **C15 PARTIAL**: `fanout`'s fail-fast preflight ported into `quality-gate`, which had none. Two
  costs the course's version omits and this port carries: the gate is **mode-scoped** (`criteria`
  is a reference mode that legitimately runs on a clean tree and is exempt), and `quality-gate`'s
  narrow `allowed-tools` allowlist had to be **widened** with the git read verbs the gate needs or
  it stalls headless. A third, found in PR review: the port must **not** copy `fanout`'s
  untracked-only stop. `fanout` stops there because its surfaces receive only the merge-base diff,
  which cannot show an unstaged file; `quality-gate` hands untracked files to the reviewer directly,
  so a new-files-only branch is a real change set and stopping on it would report "nothing to
  review" about work that is plainly there.
- **C16 ALREADY-PRESENT**: both suppression halves — repo standards override a conflicting baseline
  smell, and skip what tooling already enforces — are carried in one sentence at
  `plugins/review/agents/code-reviewer.md`, corroborated in `quality-gate/context/criteria.md` and
  `code-review/SKILL.md`. No change.
- **CI code-review lane stays quality-only** (reasoned rejection, not a phantom exclusion): the
  original "deliberately excluded" clause was a no-op — no coupling to `quality-gate` existed to
  exclude. The lane is org-owned, already declares lane-splitting doctrine, and its scope rules
  foreclose absence-of-code findings. Revisitable on demand rather than silently narrowed.
- **Container close-out review split out** to #3027: its mechanism is broken
  four ways as originally specified (no seam verb yields a closing PR; "union of merge commits"
  is the empty set under this repo's squash-merge default; the integration-branch execution shape
  has no per-item PRs at all; a container-scoped basis conflicts with `quality-gate`'s singular
  review-diff-base contract) and it was judged structurally larger than a mode addition.
  **That last judgement was wrong, and #3027 is closed.** It landed 2026-08-19 (PR #3043) as
  exactly what it was said to be too large for — a tenth `quality-gate` lens,
  `plugins/review/skills/quality-gate/context/close-out.md`, routed from `SKILL.md` with
  `close-out [--container <id>] [--dry-run]` in the argument hint. All four broken mechanisms were
  resolved in-file, the container-scoped basis becoming a documented mode-scoped override of
  SKILL.md's single diff base rather than a conflict with it. It has since been run against #2933
  itself.

## Lane W (#2939)

- **C18 ADOPTED** in `planning:wayfind` only (not generalized to work-items): human-facing
  narration refers to items by title, with the number as a link or suffix.
- **C19 ADOPTED**: Out-of-scope is for scope, not sharpness; fog never graduates there; a
  wrongly scoped item is closed + one Out-of-scope line, with no Decisions-so-far pointer.
- **C20 ALREADY-PRESENT**: map body is a stable index not a mirror; Decisions-so-far is a
  pointer INDEX; Notes are links not recaps — recorded here, not restated in the skill docs.

## Lane X (#2940)

Landed via PR #2980. This section carries the per-candidate verdicts, which until 2026-08-21
existed only as a flat lane-level `ADOPTED` in the verdict table above — C21–C23 were the one
candidate group with no lane bullet, and C23's ALREADY-PRESENT disposition had no place here to
sit. The audit detail behind C22 (fleet counts, the reworded call sites, the re-trigger
condition) belongs to the invocation-reach tracked strand in
[`mattpocock-skills.md`](mattpocock-skills.md), which owns that strand; it is not restated here.

- **C21 ADOPTED**: the one-skill-per-call authoring line — a step needing two skills is two
  Skill-tool calls, not one call naming two — landed at
  `plugins/playbooks/skills/skill-authoring/SKILL.md:180` and
  `plugins/skill-quality/skills/check/SKILL.md:161`.
- **C22 ADOPTED**: the fleet audit of the invocation-reach invariant enumerated 57 skills
  carrying `disable-model-invocation: true` and found **zero** explicit "via the Skill tool"
  violations. A follow-up pass reworded operative slash-command instructions aimed at
  user-invoked-only targets in `repo-fleet-hygiene:audit` and `claude-ops` (`inventory`,
  `audit-performance`, `audit-install-state`) to the canonical human-relay form, "tell the user
  to run /X". Standing `skill-quality:check` automation was deliberately deferred — cross-plugin
  target resolution is not cheap under the single skills-root model — so the doctrine lines in
  the two authoring surfaces carry the rule rather than a check.
- **C23 ALREADY-PRESENT**: `domain-driven-design:curate-language` triggers already key on
  concrete artifacts (glossary, domain term, vocabulary), so upstream's artifact-anchored
  `domain-modeling` rewording (`domain-modeling/SKILL.md:3`, PR #848) had nothing to add. A
  one-shot comparison, not a re-evaluation trigger.

## Lane E (#2949)

- **Rerouting recipe ADOPTED** (course "Rerouting" lesson) as a documented **re-decompose**
  flow in `work-items:decompose` — a usage pattern of existing seam verbs, not a new
  capability or skill: close unimplemented children not-planned with a superseding-direction
  comment, keep implemented children untouched, re-interview/edit the spec, regenerate the
  remaining slices through the normal draft→approve→publish steps, continue.
  `/work-items:ship` routes to it when slices no longer fit the spec.
- **Disposable-tickets / editable-spec doctrine ADOPTED** verbatim: slices are projections of
  the spec at decomposition time; when the spec moves, stale projections are closed and
  regenerated, never hand-patched.
- **Reroute boundary ADOPTED**: post-ship wrongness is a new idea → new spec (new container or
  topic), never a patch to the closed one — aligned with the archival-by-closure drift
  doctrine (Lane A). Added beyond the course: small drift is an ordinary body edit, not a
  reroute; claimed in-flight items are coordinated with, not closed from under their holder.
- **Both spec homes covered**: the flow works against the topic Brief (no container) and the
  tracker container body (Lane A's spec-on-tracker model).

## Decided at interview (2026-08-17, not per-lane)

- **Naming:** "work item" stays canonical; "ticket"/"issue" are documented first-class synonyms
  (trigger coverage landed via #2947). Rename of plugin/seam REJECTED.
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

## Adapter-track scope decision (2026-08-20)

Three seam follow-ons — #2950 (adapter-onboarding skill), #2952 (Gitea/Forgejo
adapter), #2946 (Linear adapter) — each carry an acceptance criterion requiring a **live** conformance
pass. The suite creates, claims, and closes items, so it must point at a disposable instance
and can never run against a coordination tracker.

**Decision: the Gitea live-conformance criterion is descoped. #2950 and #2952 close on what
shipped; #2946 stays open.** The maintainer's call, in their words: "I don't think we need it,
we just need linear." Gitea remains **shipped and supported** — it is the free, self-hostable
option that serves the no-paid-tool constraint this effort set for solo developers — it is
simply not being validated against a live server.

What that leaves, stated per item rather than rounded up:

| Item | Met | Not met |
|---|---|---|
| #2950 | skill with interview → live-exploration → generate → conformance-verify flow; security skeleton matching **and exceeding** the jira guards (the dot-boundary host pin went into the template, and `quote_safe` added a choke point jira never had) | end-to-end demo of a generated adapter against a **live** server |
| #2952 | generated through the skill rather than hand-written; honest capability gating (five verbs declared `false`, `sub_item_depth: 0`, and **no verb script exists for any false verb**); generator findings fixed rather than filed; `setup`'s provider comparison updated | live conformance pass |
| #2946 | adapter complete — all ten verbs implemented and unit-tested, including the lease protocol | live conformance pass |

**The one thing genuinely lost** is #2950's end-to-end proof that the generator emits an adapter
that works against a real provider. Gitea was the designated vehicle for exactly that, and Linear
cannot substitute — Linear was hand-built, so it proves nothing about the generator. The honest
size of the gap: the generated Gitea adapter passes its full mocked-transport suite, so what is
missing is "verified against a live server", not "unverified".

**Correcting a blocker reason recorded earlier in this effort.** It was written, more than once,
that no tracker instance was reachable from the build environment. That was an untested
assumption stated as fact and it is **false**: Gitea ships as a single self-contained binary with
sqlite built in, its releases are fetchable here, and a real one was downloaded and
version-verified. The actual blocker is narrower — serving it needs privileged setup (a dedicated
unprivileged user plus `cap_net_bind_service`, since Gitea declines to run as root), which the
sandbox's permission policy gates. Reachability was never the constraint.

**Do not "unblock" a future attempt by relaxing the adapter's bare-hostname rule.** Port 443 and
TLS are structural, not preferences: `wit_gitea_http` builds `https://<host>/api/v1` under
`--proto '=https'`, and `config.gitea.host` must be a bare hostname, so a high port is not
expressible. That rule exists so a PR-modifiable binding cannot smuggle URL structure and
redirect the credential off the intended tenant. Widening it to make a suite run would trade a
real security control for a green check.

Issue `#2946` **closed 2026-08-21 with its live-conformance clause descoped**, the same treatment
`#2950` and `#2952` received. An earlier version of this paragraph said it "remains open"; that was
true when written and is recorded here rather than quietly overwritten, because this section is the
durable record of the adapter track's scope decisions.

The reason it could not be met is unchanged: Linear is SaaS and cannot be self-hosted at any
permission level, so a live run needs a throwaway workspace or team plus an API key supplied
through the environment as `WIT_LINEAR_API_KEY` (the name `config.linear.auth_env` carries) —
never a coordination workspace.

What changed is the evidence that replaced it. The adapter was validated against Linear's **real
published GraphQL schema** (`@linear/sdk` 90.0.0 cross-checked against the published SDL): all 18
operations validate clean under `graphql-js`, with a negative control catching 10 of 10 injected
faults, and the pass found and fixed two real defects — a `page_size` above Linear's cap of 250
that config validation accepted, and label resolution that could see neither workspace-level labels
nor past its own first page. So what ships is **verified against the provider's schema and a full
mocked-transport suite, never against a live server** — materially stronger than "unverified", and
still short of what the criterion asked. Four resolver-level questions stay open and are named on
the issue: whether `assigneeId: null` semantically unassigns, Linear's default comment ordering,
whether `Team.labels` really excludes workspace labels, and behaviour under real rate limits and
concurrent claims.

**A claim in an earlier draft of this very section was wrong and is corrected here**, which is
worth recording given the section's subject. It said the target must be disposable "since the
suite closes what it creates." It does not. `run-conformance.sh` contains no close or delete
logic at all; cleanup is entirely the binding's `_cb_clean_at_start`, and only two bindings ever
implemented one — `github` (closing every open issue through `gh`) and `local-markdown` (a fresh
temp dir per run). The `jira`, `gitea`, and `linear` bindings shipped it as an unfilled `:`
placeholder, so a live run would have created, claimed, and mutated issues and left every one of
them behind.

The `linear` binding now implements it for real, archiving every issue in the throwaway team
through Linear's own GraphQL API rather than through the seam under test, and **failing loudly**
if that pass errors — a cleanup that quietly does nothing is worse than none, because the suite
then asserts counts against a previous run's leftovers and flaps for reasons no one can see. The
`gitea` binding and the generator's template still carry the placeholder and now say so on
stderr on every run instead of staying silent.

The reason a disposable target is mandatory is therefore stronger than the original wording
suggested, not weaker: the suite mutates real items, and outside `github` and `local-markdown`
nothing has ever cleaned them up.

## Cross-links

- Skills-repo SSOT: [`mattpocock-skills.md`](mattpocock-skills.md) (attribution table; tracked
  strands). The invocation-reach tracked strand's audit lands via lane X (#2940).
- Full v1.2 map: [`mattpocock-skills-v12-map.md`](mattpocock-skills-v12-map.md). Staleness
  fixes and absorbed-under-different-name traceability landed via #2947.
