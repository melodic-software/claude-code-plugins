# fresh-eyes-checkpoint-audit

## Brief

### TLDR

Wave 2 of program #304: retrofit fresh-context delegation into the 10 skills where same-context
judgment is structural and unmitigated, codify the delegation mechanics (dispatch shape, model
tiers, named-agent bar) as doctrine with a deterministic conformance gate, and correct two false
claims found during the audit. Wave 1 (the 50-plugin audit) was executed 2026-07-19 by five
fresh-context agents; findings and the working ledger live in
`.work/fresh-eyes-checkpoint-audit/interview-checklist.md`.

### Goal

Every skill step whose output judges work produced in the same context either delegates that
judgment per the fresh-eyes doctrine or is explicitly deferred with a trigger — and the delegation
mechanics (how to dispatch, at what model tier, when a named agent is earned) exist once, as cited
doctrine, enforced by a deterministic authoring-time gate.

### Constraints

- Doctrine home: `docs/PLUGIN-PHILOSOPHY.md` — new "delegation mechanics" section beside the
  existing fresh-eyes checkpoints section. Cite upstream sources as pointers (URL + verified date,
  the section's existing style); never restate what an official page owns.
- Conformance gate: a new check in skill-quality:check — generic (skill-quality is a published
  plugin; the check must not assume this repo's doctrine applies to third-party authors).
- Dispatch default: generic fresh-context subagent with rich inline instructions (official
  endorsed default). Named agent only when the same worker+instructions dispatches from multiple
  sites (or repeats via description-triggered direct invocation) AND a model pin or enforced tool
  restriction is load-bearing. Skills preferring an installed named agent always specify the
  generic fallback (dispatch ladder).
- Model tiers: relative ladder — consequential verdicts at session-model tier or above, never
  below; tedious/mechanical prep may drop a tier — plus one dated tier-to-model mapping table with
  a recheck trigger. Heavy default must be explicit (subagent model resolution defaults to
  `inherit`). Consumer override: `CLAUDE_CODE_SUBAGENT_MODEL` via settings `env` (single global
  knob, any scope, no forking).
- Consumer-safe by design: no userConfig model keys (per-plugin-id sprawl, verified), no
  cross-plugin runtime file references (plugin cache isolation), doctrine travels by
  authoring-time conformance baked into each skill.
- Wave shape: doctrine + gate PR first (every retrofit conforms to it), then per-plugin retrofit
  PRs (#280 precedent).

### Acceptance criteria

1. PLUGIN-PHILOSOPHY delegation-mechanics section merged: dispatch ladder, inline template
   conventions (fresh-context wording, artifact-not-story, degrade-when-absent), model-tier
   ladder + dated mapping, named-agent bar — each load-bearing claim cited to its official page.
2. skill-quality:check FAILs a skill whose declared step is nonconformant (malformed,
   unknown-class, or reason-less exemption directive) and WARNs on undeclared same-context
   judgment language — and passes all tranche-1 skills post-retrofit with zero check-18
   WARN/FAIL. *(Amended 2026-07-19 during /architect: the original "FAILs a skill that declares a
   judgment step without conformant delegation" contradicted the fuzzy-tier=WARN decision locked
   this session; plan-reviewer finding #1. Approval of this plan ratifies the amendment.)*
3. Ten retrofits merged: session-flow:retro, code-tidying:tidy (Phase G), codebase-health:audit
   (Phase 6), claude-config:audit-automation-gaps *(renamed from automation-gaps by #371, same-day
   merge — corrected 2026-07-19)* (step 6), discovery:research (outcome gate subjective
   criteria), source-control:pull-request (prep inline-fallback fenced), testing:write (advisor
   seam fresh-context non-fork), verification:confirm (refactor/fix carve-outs closed),
   planning:interview (lock-mode synthesis review pass), re-anchor correctors (escalation criteria
   replace self-triggered escalation).
4. Corrections merged: review per-slice.md `memory: local` justification verified or removed; no
   doctrine or skill text claims a tools allowlist containing Bash is read-only.
5. #304 carries the wave-1 findings comment (stale candidate list corrected); tranche-2 items
   filed as per-plugin issues, each tagged for re-judgment under default-to-delegate on next touch.

### Captured assumptions

- Default-to-delegate: when in doubt whether a judgment step is bias-exposed, delegate.
- Keep all six review agents; ci-log-auditor documented as discoverability-earned (trim candidate).
- Tranche-2 WEAK findings (≈9: songwriting filters, youtube-digest A+ spot-check, mcp-tools:audit,
  claude-memory:health, planning:prd review, planning:plan review action, explore-family outcome
  gates, event-storming:simulation SCORE loop, quality-gate restatement inline path) are
  adequately mitigated today (human-in-loop, downstream re-verification, or deterministic
  sub-gates) — deferral is a decision, not a gap.

### Out-of-scope

- Rewriting already-compliant delegation (devils-advocate, plan, quality-gate self, confirm Stage 2,
  compress, implement, debug, fanout, name-it-better, do-your-research-deep).
- Converting the tranche-1 items to deterministic gates — audited: each residual judgment is
  subjective; delegation, not scripting, is the correct fix (stance-mechanism doctrine composes
  where a future mechanical sub-check emerges).
- Hooks-only plugins (no skills, no judgment steps).

### Deferred questions

- Per-plugin model-tier granularity — no official middle seam between the global
  `CLAUDE_CODE_SUBAGENT_MODEL` and per-plugin userConfig sprawl. Trigger: a consumer needs
  per-plugin dial-down. Arbiter: USER-RESERVED (cost posture).
- Whether plugin-shipped agents honor `memory: local` — verify empirically during the corrections
  retrofit. Arbiter: /architect.
- `-deep` siblings for the four re-anchor correctors vs. escalation-criteria-only (tranche-1 does
  criteria; siblings if criteria prove insufficient). Trigger: escalation observed not firing.
  Arbiter: USER-RESERVED (scope).

## Plan

Design contract (declared patterns, check-18 semantics): `design/design-resolution.md`. Evidence:
`.work/fresh-eyes-checkpoint-audit/interview-checklist.md`.

### Phase 1: Doctrine + gate PR [TODO]

One PR: `feat/fresh-eyes-delegation-doctrine-gate`, branched from fresh `origin/main` via the
sibling-worktree flow. Every later phase depends on it. Carries this topic slice
(Brief + Plan + design/) as its first commit.

Work items, in order:

1. **Fresh-docs re-fetch (repo CLAUDE.md mandate)** — WebFetch before writing any doctrine text,
   cite URL + fetch date per load-bearing claim: sub-agents page (fresh context vs fork; model
   resolution default `inherit`; frontmatter model values), skills page (body loading/preprocessing),
   settings page (`CLAUDE_CODE_SUBAGENT_MODEL` via `env`), plugins-reference (no per-plugin model
   seam — userConfig scope). A claim that fails re-verification re-opens the affected Brief
   constraint with the user; do not silently write around it.
2. **Consumer pre-flight for the check-script contract** — grep the repo for consumers of
   check-skill.sh's check count and output shape before extending it: `seventeen` appears in
   `plugins/skill-quality/skills/check/SKILL.md` (description), `.claude-plugin/plugin.json`
   (description), `README.md` (×2), and `docs/MIGRATION-PLAYBOOK.md:984`; `check-skill.test.sh`
   consumes FAIL/WARN line formats. Re-grep at execution and capture the full list in the PR.
3. **Fleet WARN baseline** — run check-skill.sh over every `plugins/*/skills/*` skill pre-change;
   store per-skill PASS/FAIL + warning counts in `.work/fresh-eyes-checkpoint-audit/baselines/`
   (memory slice, never committed), alongside the environment knobs that skew WARN counts
   (npx present? `CHECK_SKILL_SKIP_MARKDOWNLINT`?) — baseline and comparison runs must share an
   environment or the delta triage is corrupt. Fleet pass ≈ 8 min at ~3.4 s/skill × 141 skills.
4. **`docs/PLUGIN-PHILOSOPHY.md` — new `## Delegation mechanics` section** beside
   `## Fresh-eyes checkpoints`, pointer-style citations (URL + verified date), never restating
   official pages. Contents (Brief criterion 1): dispatch ladder (generic fresh-context subagent
   with rich inline instructions = default; named agent preferred where installed, generic fallback
   always specified); inline-template conventions (fresh-context wording, artifact-not-story,
   degrade-when-absent); named-agent bar (multi-site same-worker repetition — or repeated
   description-triggered invocation — AND load-bearing model pin or enforced tool restriction);
   model-tier ladder (consequential verdicts at session tier or above, never below; mechanical prep
   may drop a tier) + one dated tier-to-model mapping table with recheck trigger + heavy-default-
   must-be-explicit note (subagent model resolution defaults to `inherit`) + consumer override
   `CLAUDE_CODE_SUBAGENT_MODEL` (settings `env`, single global knob); tool-cage framing (an
   allowlist containing Bash bars Edit/Write + recursive spawning — it is NOT read-only); the two
   declared patterns + exemption classes exactly as `design/design-resolution.md` specifies.
5. **Reconcile the existing `## Fresh-eyes checkpoints` wording** — "A named subagent removes it"
   → fresh-context (non-fork) subagent, generic or named; keeps the merged doctrine
   self-consistent with the generic-dispatch default. No other content change.
6. **`check-skill.sh` check 18** — implement the semantics table and scan-mechanics constraints in
   `design/design-resolution.md` verbatim (normative): row-precedence order, vendor/evals
   exclusion, fence-aware detectors, per-file proximity with spoke-limitation WARN wording,
   POSIX-ERE-only regex list seeded from the ten audited skills' AND the exempted steps' phrasing,
   tunable proximity constant beside the existing caps.
7. **`check-skill.test.sh` fixtures** — minimum: FAIL malformed directive, FAIL unknown class,
   FAIL missing reason, WARN undeclared judgment language, WARN stale directive, PASS delegation
   prose (both `fresh-context` and `fresh context` forms), PASS valid exemption, PASS
   judgment-language + directive examples inside code fences (self-reference guard), PASS skill
   with no judgment language.
8. **Consumer-facing pattern spec inside the plugin** — new `plugins/skill-quality/.../reference/`
   page carrying the mechanical contract (directive grammar, classes, canonical wording,
   semantics table); check-18 FAIL/WARN messages point to it so third-party authors can read the
   rule being enforced without this repo's doctrine. PLUGIN-PHILOSOPHY cites the plugin as spec
   owner (add the row to its convention registry: pattern contract → skill-quality plugin).
9. **skill-quality packaging** — SKILL.md and `plugin.json` descriptions `seventeen-check` →
   `eighteen-check` (quoted trigger phrases untouched — check 3 guards this), checks list +
   gotchas updated (incl. the spoke-proximity limitation and stale-WARN advisory framing);
   `docs/MIGRATION-PLAYBOOK.md:984` count updated; README (×2 counts) + CHANGELOG entries;
   `plugin.json` minor version bump.
10. **Cross-platform honesty** — fence/span scanner in POSIX awk/ERE; run a macOS smoke pass or
    record the manual-verification gap per the repo's cross-platform contract. While in the
    script: existing check 17 uses GNU-only `date -u -d` (silently no-ops on BSD/macOS) — fix or
    annotate the recorded gap there too (precedent that BSD breakage ships silently).

**Sanity Check:**

- `bash plugins/skill-quality/scripts/check-skill.test.sh` exits 0 (new fixtures included).
- Fixture demo of amended criterion 2's FAIL half: the malformed-directive fixture exits 1 with a
  `FAIL:` line naming check 18.
- Fleet run recipe (baseline item 3 uses the same): from repo root,
  `for p in plugins/*/skills; do for s in "$p"/*/; do CHECK_SKILL_SKILLS_ROOT="$p" bash plugins/skill-quality/scripts/check-skill.sh "$(basename "$s")"; done; done`
  — zero NEW `FAIL:` lines vs the item-3 baseline (fuzzy tier is WARN-only); WARN deltas recorded
  per skill. Expected WARN gainers: the tranche-1 ten (cleared by Phase 2) and the tranche-2 ≈9
  (cleared by Phase 4's deferred-directive sweep); any OTHER gainer is triaged before merge.
- `sed -n '/^## Delegation mechanics/,/^## /p' docs/PLUGIN-PHILOSOPHY.md | grep -c "verified 2026-"`
  ≥ 4 — citations dated inside the new section; `grep -c "fresh-eyes-exempt" docs/PLUGIN-PHILOSOPHY.md` ≥ 1.
- `npx markdownlint-cli2` clean on every changed markdown file; `shellcheck` clean on the script.
- `grep -rn "seventeen" plugins/skill-quality docs/MIGRATION-PLAYBOOK.md` returns no stale count.

### Phase 2: Per-plugin retrofit PRs — 10 skills [TODO]

Gated on Phase 1 merge (doctrine is the spec; check 18 is the verifier). One PR per plugin
(#280 precedent). **Step 0 per PR (mandatory):** re-verify the audited step against current
`origin/main` before retrofitting — this repo merges multiple PRs per day and one target was
already renamed same-day (#371); divergence reopens that row, not the wave.

| PR | Skill(s) | Retrofit (from Brief criterion 3) |
|---|---|---|
| session-flow | retro | 5-dimension quality assessment + self-score → fresh-context dispatch |
| code-tidying | tidy (Phase G) | self-review of own diff → fresh-context dispatch |
| codebase-health | audit (Phase 6) | fix-mode self-review → fresh-context dispatch (align with its Phase 2 validator) |
| claude-config | audit-automation-gaps (step 6 as audited pre-rename; re-anchor to current text) | pattern-consistency self-review → fresh-context dispatch |
| discovery | research (outcome gate) | subjective criteria (4/7/8) → fresh-context judge; mechanical criteria stay exempt (`deterministic-gate`) |
| source-control | pull-request (prep 1.2) | inline fallback fenced with explicit criteria or exemption |
| testing | write (advisor seam) | advisor becomes fresh-context non-fork |
| verification | confirm | refactor/fix sub-judgment carve-outs closed |
| planning | interview (lock mode) | fresh review pass on lock-mode synthesis before presenting |
| re-anchor | shared `plugins/re-anchor/context/re-anchor-audit-correct.md` + ALL 11 skills referencing it | explicit escalation criteria replace self-triggered escalation in the shared spoke; per the design contract, each skill's OWN SKILL.md anchors its declaration (check 18 does not scan plugin-level spokes — without per-skill anchors this PR's gate check is vacuous) |

Each PR also bumps that plugin's `plugin.json` version + CHANGELOG entry — no CI gate enforces
this for these plugins, and without it installed consumers never receive the retrofit.

Each PR: apply doctrine wording (canonical prose; exemption directives where a class genuinely
applies), then run the gate on every touched skill.

**Sanity Check (per PR):** from repo root,
`CHECK_SKILL_SKILLS_ROOT=plugins/<plugin>/skills bash plugins/skill-quality/scripts/check-skill.sh <skill>`
exits 0 with no check-18 WARN line; post-commit re-run adds
`CHECK_SKILL_BASE_REF=$(git merge-base HEAD origin/main)` on a clean tree so check 3
(trigger preservation) actually diffs the change; markdownlint clean. Baseline-delta comparison
(the WARN this PR clears) runs in the MAIN session against
`.work/fresh-eyes-checkpoint-audit/baselines/` — worktree workers only run the gate-exits-0 check
(the memory slice does not exist in sibling worktrees).

### Phase 3: Corrections PR — review plugin [TODO]

Gated on Phase 1 merge (cites the doctrine's tool-cage framing). Brief criterion 4:

1. **`memory: local` empirical verification** — protocol: (a) fresh-docs fetch of the memory and
   sub-agents pages first (repo mandate; confirms the documented persistence location and current
   flag names); (b) build a minimal local plugin shipping an agent with `memory: local`; load it
   with the plugin-dir flag the fetched docs name; (c) in session 1, induce a memory write with a
   known sentinel string; (d) in a SEPARATE session 2, invoke the agent again and check both the
   documented persistence location on disk and whether the sentinel is recalled. Verified → keep
   per-slice.md:45 justification, add citation; refuted → remove the "adds persistent memory
   across sessions" claim; inconclusive after two attempts → user gate (see Handoff).
2. **Read-only claims sweep — repo-wide** (criterion 4 says "no doctrine or skill text", not
   review-only): `grep -rniE "read[- ]?only|readonly" docs/ plugins/` hand-audited (spot-check
   reworded forms — "review-only", "does not modify" — during the audit); fix every claim that a
   Bash-holding tools allowlist is read-only. Bulk sits in `plugins/review/` (README, plugin.json,
   agent bodies, quality-gate prose) — reframed to the doctrine's cage wording. Keep accurate
   narrow uses (e.g. "reviewed code stays unmodified", by-instruction boundaries clearly labeled
   as instruction-only). Coordinate: verification:confirm's own line rides its Phase 2 PR.

**Sanity Check:** repo-wide `grep -rniE "read[- ]?only|readonly" docs/ plugins/` output hand-audited with
per-hit disposition recorded in the PR body — zero remaining allowlist-with-Bash-is-read-only
claims; memory-verification transcript summary + disk-location evidence recorded in the PR body;
`CHECK_SKILL_SKILLS_ROOT=plugins/review/skills bash plugins/skill-quality/scripts/check-skill.sh quality-gate`
exits 0.

### Phase 4: Tranche-2 filing + program close-out [TODO]

1. Search-before-create (`gh issue list --search` per plugin) — then file the ≈9 tranche-2
   per-plugin issues (list in Brief assumptions), each tagged for re-judgment under
   default-to-delegate on next touch, each linking #304. On a search match: update that issue
   instead (pivot path), and record the search outcome below. Capture each resulting issue NUMBER
   in this file as filed.
2. **Deferred-directive sweep PR** — one PR adding
   `<!-- fresh-eyes-exempt: deferred -- re-judge on next touch, #<issue> -->` to each tranche-2
   skill's judgment step, citing its filed issue, plus that plugin's version bump + CHANGELOG
   entry (≈9 plugins). The sweep itself is a mechanical materialization EXEMPT from the
   re-judgment touch-trigger it installs; re-judgment enforcement is the directive's issue
   citation, not the gate. End state: zero UNEXPLAINED check-18 WARN fleet-wide (explained =
   dispositioned via the design contract's WARN ladder; literal zero would force rewording
   compliant skills or diluting the regex list into tautology).
3. #304: comment linking merged PRs against the five acceptance criteria (as amended); correct any
   remaining stale candidate-list entries.
4. `/planning:architect close-out` on the final PR: PLAN.md into the PR description, ADR admission
   test on the declared-pattern contract decision, prune the topic slice with pointers.

**Sanity Check:** every issue number captured in item 1 exists and its body contains the
re-judgment tag + #304 link (`gh issue view <n>` per captured number — no search-count matching);
fleet run recipe from Phase 1 reports zero unexplained check-18 WARN after item 2, with each
explained WARN's disposition recorded beside the baseline; topic slice deleted in the final
commit.

## Blast radius

MEDIUM. New convention + enforcement mechanism constraining all future skill authoring (a
stress-test trigger), and skill-quality is a published plugin — third-party authors hit check 18.
Mitigations: authoring-time gate only (not wired into CI), fuzzy tier WARN-only by design, all
changes git-revertible, no runtime behavior change for consumers of the other 49 plugins.

## Stress-test summary

Two fresh-context rounds, 2026-07-19, findings verified against the repo then applied:

- **Plan-reviewer (Step 3):** 1 CRITICAL, 8 IMPORTANT, 5 SUGGESTION. Load-bearing: Brief
  criterion 2 contradicted the user-locked WARN-only fuzzy tier (criterion amended, ratified at
  approval); vendor/evals had to leave the scan surface; self-referential-linter fence problem;
  fleet WARN-noise disposition; cold-executable sanity commands; published-plugin spec home
  (pattern spec now ships inside skill-quality).
- **Devils-advocate (Step 4):** 2 HIGH, 7 MEDIUM, 4 LOW; verdict "architecture sound, not
  survivable as written" — all pre-approval items applied: re-anchor's judgment step lives in a
  plugin-level shared spoke outside the generic checker's reach (declaration now anchors
  per-skill; PR rescoped to the shared file + all 11 skills); WARN-disposition ladder + curation
  policy added to the design contract and Phase 4 target softened to "zero unexplained";
  claude-config skill name stale same-day (#371 rename — corrected, plus mandatory per-PR
  freshness step 0); CRLF tolerance + inline-code-span awareness + fenced-only literals made
  normative (the gate would otherwise FAIL its own spec page). Trackable items folded into
  phases: per-PR version bumps/CHANGELOGs (nothing enforces them), macOS verification honesty
  (existing check-17 `date -d` precedent), phase-tag batching, env-pinned baselines, broadened
  criterion-4 grep. Research-iterate loop not needed — no finding survived verification
  unresolved (1 iteration).

## Execution shape

Sequential across phases with one parallel wave inside Phase 2:

- Phase 1 gates Phases 2 and 3 (doctrine = retrofit spec; corrections cite cage framing).
- Phases 2 and 3 are file-disjoint (10 plugins vs review plugin) — may run concurrently.
- Phase 2's ten PRs are mutually file-disjoint — parallel-safe in worktree-isolated waves of 2–3
  sub-agent workers; cost: N workers multiply tokens vs one sequential session. Sequential
  fallback: main session executes PR-by-PR in the table order.
- Phase 4 last (needs merged PR links).

| Phase | Surface | Basis |
|---|---|---|
| 1 | main session | judgment-heavy doctrine prose + script design |
| 2 | sub-agent workers, waves of 2–3 (worktree-isolated) — or sequential main session | mechanical once doctrine locks; file-disjoint |
| 3 | main session | empirical verification requires live plugin-install judgment |
| 4 | main session | tracker writes + close-out |

PLAN.md edits stay main-session-only; workers report back.

## Open questions

- USER-RESERVED (do not self-resolve; from Brief): per-plugin model-tier granularity; re-anchor
  `-deep` siblings vs escalation-criteria-only.
- DEFERRED with trigger (devils-advocate #5): check-18 fleet pass is authoring-time only — no CI
  or fleet-audit wiring exists, so WARN-clean state decays with the first un-gated edit. Trigger:
  first observed regression after wave 2 merges → wire a fleet check-18 pass into ci.yml or the
  fleet-hygiene audit cadence. (Rescue-time correction: no interim recheck mechanism exists —
  the repo-fleet-hygiene audit inventories git/GitHub state only and never invokes the skill
  gate, so until the trigger fires the WARN-clean invariant is unmonitored; the resuming
  implementer picks the recheck mechanism.)

## Handoff to implementation

### User-approval gates

- [FALLBACK — confirm or override] Brief criterion 2 amendment (plan-reviewer finding #1):
  approval of this plan ratifies the reworded criterion; overriding it reopens the fuzzy-tier
  decision instead.
- Before Phase 2 fan-out: confirm parallel workers (token cost) vs sequential.
- Phase 3 item 1: if `memory: local` verification is inconclusive after two attempts, surface to
  the user rather than deciding removal unilaterally [FALLBACK — confirm or override].
- Any doctrine claim that fails the work-item-1 re-fetch reopens the affected Brief constraint with
  the user.

### Execution shape ([EXEC-SHAPE] tagged)

- [EXEC-SHAPE] Exemption reason required — missing `-- <reason>` FAILs (user standard: justification
  at the suppression site).
- [EXEC-SHAPE] Stale-directive WARN (ESLint `reportUnusedDisableDirectives` precedent).
- [EXEC-SHAPE] Scan surface = SKILL.md + internal spoke dirs (audited judgment steps live in
  `context/*.md`).
- [EXEC-SHAPE] Fresh-eyes section wording reconciliation folded into Phase 1 (doctrine
  self-consistency with generic-dispatch default).
- [EXEC-SHAPE] re-anchor's shared spoke + all 11 skills = one PR (matching the Phase 2 row
  above; an earlier draft said four — corrected at rescue time); one PR per plugin otherwise
  (#280 precedent).
- [EXEC-SHAPE] Directive token `fresh-eyes-exempt`, namespaced per linter precedent.
- [EXEC-SHAPE] Canonical delegation wording matches both `fresh-context` and `fresh context`
  (POSIX ERE `fresh[- ]context`) — already-compliant skills use both forms; matching beats a
  fleet-wide rewording sweep.
- [EXEC-SHAPE] Scan surface excludes `vendor/` and `evals/` (vendor is byte-frozen per check 8 —
  findings there would be permanently unclearable); detectors are fence-aware (self-reference
  guard for docs showing literal examples).
- [EXEC-SHAPE] Mechanical pattern spec ships inside skill-quality (`reference/` page, pointed to
  by check-18 messages); PLUGIN-PHILOSOPHY carries rationale and registry row (published-plugin
  constraint — third-party authors need a readable spec).
- [EXEC-SHAPE] Phase 4 deferred-directive sweep PR materializes tranche-2 deferrals at the
  suppression site (fleet ends WARN-clean; each directive cites its issue).
- [EXEC-SHAPE] Criterion-4 sweep runs repo-wide (criterion text says "no doctrine or skill
  text"), bulk in plugins/review; verification:confirm's own line rides its Phase 2 PR.
- [EXEC-SHAPE] Declarations anchor in each skill's own scanned files even when judgment mechanics
  live in a plugin-level shared spoke (generic checker cannot assume plugin layout; re-anchor PR
  rescoped to shared spoke + all 11 skills).
- [EXEC-SHAPE] Every Phase 2–4 PR bumps its plugin's version + CHANGELOG (no CI gate enforces it;
  without it installed consumers never receive the change).
- [EXEC-SHAPE] Fleet end-state target = zero UNEXPLAINED check-18 WARN, with the design contract's
  disposition ladder + skill-quality-owned regex curation policy (literal zero would dilute the
  heuristic into tautology).
- [EXEC-SHAPE] Phase-tag updates batched into the close-out PR (protects Phase-2 parallel wave
  from PLAN.md merge conflicts).
- [EXEC-SHAPE] Phase ordering 1 → (2 ∥ 3) → 4.

### Mechanical work

- Sibling-worktree flow per branch; branch names `feat/<topic>` (repo convention `<type>/<description>`).
- Conventional-Commit PR titles (squash merge; pr-title.yml enforces).
- Commit checkpoints at each green Sanity Check; topic slice rides Phase-1 branch
  (`contract_tier: branch` default). Phase-tag updates are BATCHED into the Phase-4 close-out PR
  (per-PR tag edits would put PLAN.md into every "file-disjoint" retrofit PR and serialize the
  parallel wave on merge conflicts); mid-wave status lives in the memory-slice checklist instead.
- Sequential fallback for Phase 2 documented above; scope-fence violation by any worker → stop the
  wave, revert to sequential.
