# pocock-course-lanes — steering-section addendum

Extends the six-lane contract in `PLAN.md` (branch `claude/plan-mode-discussion-55kszx`,
unmerged when this was written) with the course's **Steering** section: nine lessons pasted and
inventoried in the 2026-08-17 steering-section session (branch
`claude/pocock-steering-course-00zkvd`). Same contract rules apply: interview-first per lane,
claim ladder, lanes discuss and decide but do not implement, decision rows land in
`docs/upstream/aihero-course.md` (lane 6's deliverable), coverage index closes in lane 6.

**PLAN.md amendment pending:** its Goal/acceptance say "six lanes"; when the contract branch
merges, extend the lane index with lanes 7–9 below and re-scope lane 6's coverage index to
include the nine steering lessons.

## Session outcome (2026-08-17)

The session re-evaluated the SSOT's `writing-for-agents` rejection and superseded it: parity
holds only for the pruning/audit half. Full section-by-section verdicts:
`docs/upstream/mattpocock-skills.md` → "writing-for-agents decomposition". Corrections landed
in this session; substance rides the lane issues.

Interview decisions (user-confirmed):

- **Authoring-time doctrine** → a NEW authoring skill (adapted, not vendored/wrapped), with
  trigger reliability as a first-class design constraint (user concern: the skill only helps
  if it fires at the writing moment; hook-forced loading judged probable overengineering).
- **Invocation-mode posture** → evidence-driven rubric; neither upstream's user-invoked
  default nor our model-invoked default assumed correct.
- **Tracking** → issues filed per lane (below); mapping-doc correction done in-session.
- **Terminology** ("sediment", "cache", "push/point", "context load", "navigation pointer",
  "cognitive load") → candidates handed to lane 6 (#2904) term adoption, not decided here.

## Steering lane index (filed 2026-08-17)

| Lane | Issue | Scope | Lessons covered |
|------|-------|-------|-----------------|
| 7 authoring doctrine | [#2909](https://github.com/melodic-software/claude-code-plugins/issues/2909) | new authoring skill; context-pointer wording, information hierarchy, completion criteria, two loads, leading words + negation | 1, 2, 4 (authoring half), 7 (parity rows) |
| 8 invocation mode | [#2910](https://github.com/melodic-software/claude-code-plugins/issues/2910) | invocation rubric, setup-convention doc, 17 missing keys, router pattern, invocation-reach invariant, fleet re-grade (ADR 0005-bounded) | 3, 4 (invocation half), 5 (incl. cloud-scope caveat) |
| 9 steering validations | [#2911](https://github.com/melodic-software/claude-code-plugins/issues/2911) | claude-memory:audit nav-pointer criteria, design-smell caveat, auto-memory parity, /init-then-prune eval fixture, steering harness-claims bundle | 6, 8, 9 + leftovers of 1–2 |

Lesson key: 1 The Steering Map · 2 Steering With A Pointer · 3 What Are Agent Skills ·
4 Write A Skill · 5 User Vs Project Skills · 6 Navigation Pointers · 7 Pruning ·
8 Trying Out Pruning · 9 Claude Code's Automatic Memory.

Suggested run order: 7 → 8 → 9 (impact order; 7 and 8 both feed lane 6's harvest, so all three
should close before lane 6 does).

## Lane 7 decision rows (closed 2026-08-17)

Interview-first per contract; register gate clean (12/12); user confirmed. Design contract:
`docs/topics/authoring-steering-skill/PLAN.md`. Rows for lane 6's `aihero-course.md` harvest:

| Claim / concern (lesson) | Verdict | Detail |
|---|---|---|
| Authoring-time doctrine needs a firing home at the writing moment (L1, L2, L4) | ADOPT | New skill `docs-hygiene:write-for-agents` — model-invoked, write-side complement to the audit siblings; design contract in the topic PLAN.md; built via filed implementation issues |
| Scope = agent-consumed docs (L4) | ADOPT (generalized) | User-widened beyond upstream's skills/AGENTS.md/CLAUDE.md: any agent-consumed markdown in the repo; auto-read surfaces are the high-value core, grounded in a docs-verified enumeration (research artifact in topic memory slice; adapted into the skill's reference) |
| Completion-criteria doctrine (L4) | ADOPT (both moments) | Write-side in the new skill; audit-side as a new `skill-quality:check` criterion so the existing fleet gets graded too |
| Two loads — cognitive load as budget (L1) | ADOPT | Doctrine operates in the skill body; PLUGIN-PHILOSOPHY Instruction economy gains a one-line cross-reference |
| Leading words + negation (L4) | ADOPT | Folded into the skill design; SSOT tracked strand retires when the implementation merges (cross-links the interview-batch-rounds deferral) |
| Pointer wording: cover branches, front-load leading word (L2) | ADOPT (adapted) | Inline in the skill; pointer-quality criteria stay pointed-at in `audit-progressive-disclosure` |
| Trigger enforcement via hook (session-start or otherwise) | REJECT | Probable overengineering (user-decided); trigger reliability instead gated by a shipped plugin-eval suite — positives per trigger family fire, negative controls don't, all-pass gates the implementation PR |
| Vendoring/wrapping upstream `writing-for-agents` | REJECT | Adapted new skill, house doctrine and naming grammar; SSOT decomposition table carries provenance |
| Pruning doctrine (L7) | PARITY — no work | Three pruning tests confirmed covered at parity or stronger (SSOT decomposition table: extract-ssot, audit-derivability, audit-instructions/unhobble) |
| Cross-skill invocation phrasing (upstream `.agents/invocation.md`) | ROUTE | Stays lane 6's candidate (#2904); lane 8 owns invocation doctrine; the new skill's body stays silent on it |

Lane 7 status: CLOSED 2026-08-17 — Brief locked (`docs/topics/authoring-steering-skill/PLAN.md`),
surface enumeration verified and committed (`docs/topics/authoring-steering-skill/design/agent-doc-surfaces.md`),
build filed as [#2962](https://github.com/melodic-software/claude-code-plugins/issues/2962)
(skill + evals + philosophy cross-ref) and
[#2963](https://github.com/melodic-software/claude-code-plugins/issues/2963) (audit-side
criterion), SSOT annotated. Next: lane 8 (#2910).

## Lane 8 decision rows (closed 2026-08-17)

Interview-first per contract; register gate clean (8/8, brief=ok); user confirmed. Contract:
`docs/topics/invocation-mode-doctrine/PLAN.md`. Rubric (the doctrine artifact):
`docs/conventions/invocation-mode/README.md`. Rows for lane 6's `aihero-course.md` harvest:

| Claim / concern (lesson) | Verdict | Detail |
|---|---|---|
| Invocation choice needs a decision rubric (L3, L4) | ADOPT (adapted — inverted default) | Rubric adopted with model-invoked default + three exception classes (side-effect/manual-timing, setup, maintainer-only) — the inverse of upstream's user-invoked default. Home: `docs/conventions/invocation-mode/README.md` + convention-registry row; cross-linked from PLUGIN-PHILOSOPHY (setup contract, Instruction economy); `playbooks:skill-authoring` pointer filed |
| Upstream's user-invoked default (L4) | REJECT | Solo-operator posture; materially weakened by mattpocock/skills#693 (desktop/web drop user-invoked skills from the listing) and by this marketplace's multi-repo discoverability need |
| Splitting by invocation (L4) | ADOPT (routed) | The rubric owns the split axis; `docs-hygiene:write-for-agents` (#2962) when-to-split doctrine points at it (lane 7 decision honored) |
| Router-skill pattern (L4 / MECHANICS) | REJECT (with reason) | Under the model-invoked default the always-present listing IS the router; `disable-model-invocation: true` skills are deliberately model-invisible. Human-side answer: `docs/SKILL-CHEAT-SHEET.md` + `claude-ops:inventory`. Domain-scoped composition routers (`discipline:sweep-all` precedent) remain an admitted distinct pattern |
| Explicit `disable-model-invocation` on every skill (L4) | ADOPT | 17 missing-key skills normalized to explicit `false` + new `skill-quality:check` criterion requiring the key — filed implementation follow-on |
| Setup-skill convention (L3/L4) | PARITY — no work | Already documented: PLUGIN-PHILOSOPHY "Setup is explicit and repeatable" (landed `967db56c`, pre-dating #2910's "documented nowhere" premise) |
| User vs project scope + cloud caveat (L5) | ADOPT | Remote/cloud sessions never load `~/.claude` user scope — project/marketplace skills are the only steering that reaches them; recorded as the rubric's surface-coverage/cloud-scope evidence axis |
| Invocation-reach invariant (MECHANICS) | CONFIRMED | Docs-verified 2026-08-17 (`true` → model-invisible everywhere, human `/name` only); SSOT strand records CONFIRMED with the audit-side trigger kept, upstream-release trigger retired |

Fleet re-grade (ADR 0005-bounded, executed in-lane): 10 non-setup `true` skills graded — 9 KEEP,
1 FLIP (`planning:questionnaire` → model-invoked, filed). The 47 setup skills are class (ii) by
contract; the 137 `false` skills conform to the default and were not swept.

Lane 8 status: CLOSED 2026-08-17 — Brief locked
(`docs/topics/invocation-mode-doctrine/PLAN.md`), rubric homed
(`docs/conventions/invocation-mode/README.md` + registry row + philosophy cross-refs),
enforcement filed (explicit-key normalization + check criterion + skill-authoring pointer), flip
filed (`planning:questionnaire`), SSOT gap-3 rows dispositioned and strand CONFIRMED. Next:
lane 9 (#2911).

## Lane 9 decision rows (opened 2026-08-17)

Interview-first per contract; round-1 decisions user-confirmed ("go with all recommendations").
No separate topic Brief — lane 9 designs nothing; these rows plus filed items are the record
(user-decided, Q1). Deviation note: rows land here per chain convention, not in
[#2911](https://github.com/melodic-software/claude-code-plugins/issues/2911)'s stated
`docs/upstream/aihero-course.md` target (lane 6's deliverable). Rows for lane 6's harvest:

| Claim / concern (lesson) | Verdict | Detail |
|---|---|---|
| Navigation sections in CLAUDE.md ("highways") vs audit C5 flagging codebase descriptions (L6) | ADOPT (adapted) | Filed criteria patch: C5 carve-out distinguishing curated navigation pointers to non-obvious, load-bearing docs (KEEP branch) from file-by-file inventories Claude can rebuild (still FLAG). Marked as repo extension if official docs state no navigation posture (provenance rule: `update` must not overwrite) |
| Stale-pointer risk — "a stale highway is worse than no highway" (L6) | PARITY — no new check | `claude-memory:audit` C7 already FAILs on referenced paths that do not exist; the filed patch adds a one-line C7 note naming stale pointers as the standing cost of navigation sections |
| Nested/subdirectory CLAUDE.md as a placement destination (our extension; course omits it) | ADOPT | C3 placement-table row ("subdirectory-specific conventions → nested CLAUDE.md") in the same filed patch; loading-semantics wording gated on harness-claim verification |
| @-mention as the one-turn-scoped pointer equivalent (L2/L6) | ADOPT | One-line distinction on C3's import row: conversational @-mention is one-turn steering, cheaper than a permanent pointer for one-off needs; `@path` imports in CLAUDE.md load at launch (already priced). Same filed patch |
| Design-smell caveat: a pointer mirroring changes across distant folders can mask low cohesion (user-raised) | ADOPT | Homed in the criteria patch's remediation guidance (restructure-before-pointer consideration at the audit's fix moment); coordination comment on [#2962](https://github.com/melodic-software/claude-code-plugins/issues/2962) points the authoring skill at it — no duplicated doctrine |
| /init-then-prune eval fixture (L8, user-suggested) | ADOPT | Filed against `claude-memory:audit`'s existing eval suite: static bloated-CLAUDE.md fixture (the shape `/init` produces) in the eval's `files`, graded against expected findings (C1/C2/C5); regression gate on audit judgment quality. Static fixture chosen over live `/init` generation (determinism) |

Lane 9 status: IN PROGRESS — remaining (research-gated): auto-memory parity rows (L9),
harness-claims verdict table (7 fresh claims + lane-8 reuse), lessons 1–2 leftover rows, term
candidates to lane 6, work items filed, close-out.
