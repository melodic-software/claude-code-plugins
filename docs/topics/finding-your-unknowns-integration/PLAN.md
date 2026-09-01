# finding-your-unknowns-integration

## Brief

### TLDR

Integrate the verified "Finding Your Unknowns" corpus (Thariq Shihipar's field guide, its
X-Article draft, the 13 html-effectiveness pages, and the context-engineering companion;
slice `finding-your-unknowns-0f25bd45`) into this repo as judgment-preserving deltas on
existing skills plus a small set of citable reference docs, gated by a scripted
comparison-evidence pass over the ~20 named-skill collisions.

### Goal

Every corpus decision in
`.work/finding-your-unknowns/finding-your-unknowns-0f25bd45/corpus-inventory.md` reaches a
disposition (adopt / adapt / compare-then-adopt / cite / drop / treat-as-caution) that is
either executed as a repo change or recorded with its reason, with no silent drops.

### Constraints

1. Vehicles (interview Q1): (a) augmentation of existing skills and (b) citable
   reference/convention docs are the primary vehicles; at most 2 genuinely new thin skills,
   each only where the evidence pass confirms a real gap; CLAUDE.md/rules changes only if
   the context-engineering material earns one on its own evidence.
2. Codification posture (Q2, BINDING): honor the source author's anti-premature-codification
   warning — only judgment-preserving deltas (output contracts, checklists, conventions with
   rationale); no generator-style "make me an X" skills; the warning itself is quoted in
   whatever reference doc graduates.
3. Evidence discipline (Q3): adopt/adapt verdicts on named-skill collisions are CONDITIONAL
   ("adopt X into S if S lacks it") until a read-only evidence pass grades each named skill
   against its checkable claims; only surprises return to the human.
4. Vendor-claim discipline (Q5): corpus claims are vendor-blog anecdote unless the targeted
   live-doc check (folded into the evidence pass) verifies them; the ~6 decision-relevant
   harness claims (auto-memory, /doctor, ToolSearch deferred loading, artifacts-as-context,
   80%-claim scoping, rich references) get that check; nothing else does.
5. House style: all new prose obeys the repo's ai-slop/house-style rules
   (.claude/rules/vendor-docs-are-not-style.md); citation shape follows
   plugins/knowledge/reference/citation-shape.md (URL + retrieval date + content hash).
6. Execution contract (Q6): each conditional-batch unit is closed only when its verdict is
   executed-or-recorded and the inventory row links the outcome; no silent drops.
7. Vehicle placements (Q7-Q10): the five-pass sequencing lands as a workflow section in the
   central reference doc with cross-refs from planning:wayfind and session-flow:workflow (no
   new orchestration skill); the reference doc owns the prompt-pattern catalog with one
   canonical invocation line per owning skill; reply-affordance is a house convention
   (default-with-judgment) owned by the doc with an artifact-design cross-ref.
8. Evidence-gate classification (sign-off S1): every delta is classified per-row under
   PLUGIN-PHILOSOPHY's rubric (docs/PLUGIN-PHILOSOPHY.md:699-742). CONTRACT/POLICY/CONVENTION
   rows land now as team conventions adopted by the sign-off; DOC rows are citation/doc
   lines; BEHAVIORAL rows never land as standing instructions — they become reference-doc
   heuristic lines plus candidate eval cases, awaiting observed-stumble evidence.
9. Registry discipline (sign-off S2): convention-registry rows for reply-affordance and
   export-button only, each with an explicit conformance surface, landing owner-doc-first
   (owner doc before a second adopting plugin, PLUGIN-PHILOSOPHY:594-595).
10. Sequencing with docs/topics/context-engineering-claude-5/ (sign-off S3): this effort
    never edits that topic's audit-instructions criteria files; Wave 1 records F2's three
    candidates in that topic's PLAN plus a Phase-10 re-inventory/rebase note; no freeze.
11. Schema stability (sign-off G.4 / D37): the `### Phase N` heading/tag vocabulary and any
    parsed schema (check-open-questions.sh fields) are never renamed without a version bump
    and changelog; block reordering is safe.

The complete signed decision surface — classified delta roster (D/E/F/G rows), wave
assignments, per-finding dispositions — is ./signoff-sheet.md (rev 2, operator-confirmed
".confirm all" on 2026-09-01).

### Acceptance criteria

(Signed off with the sheet, 2026-09-01; sign-off sheet Part G.5.)

1. Every decision in corpus-inventory.md has an executed-or-recorded disposition traceable
   from ./signoff-sheet.md — verified by grep over the disposition lines, not asserted.
2. All waves green on the per-plugin gates: version bump + CHANGELOG entry;
   check-changed-skills.sh (trigger-keyword preservation, listing cap, --require-evals);
   listing budget respected; cheat-sheet regenerated once per PR series, series sequential;
   scripts/affected-tests.sh --run green.
3. The F1 reference doc carries the quoted anti-premature-codification warning and the C6
   permission/quoting basis in its header.
4. Registry rows (reply-affordance, export-button) carry explicit conformance surfaces and
   land owner-doc-first.
5. docs/topics/context-engineering-claude-5/PLAN.md carries the S3 sequencing rows.
6. Every Wave-2/Wave-3 contract delta lands with eval expectations in the same commit as
   its contract lines (sign-off Part D eval-impact column).
7. /planning:plan consumes ./signoff-sheet.md + this Brief as its input contract.
8. Delivery (operator amendment at sign-off): all execution in one session on branch
   claude/reading-feedback-j4sg96, delivered as ONE pull request; waves are commit
   ordering, not separate PR series; deferred items may become filed issues.

### Captured assumptions

- The published blog is the canonical citation source for wording; the X draft is citable
  only for draft-only content (5 images, 3 links) — per corpus V7.1.
- Arm-B verification ran degraded (same-vendor adversarial refuter); accepted as sufficient
  for this corpus.

### Out-of-scope

- Watching/transcribing the two linked videos (companion-classified; no ingest path).
- Re-digesting the 3 referenced-external related-posts articles.

### Deferred questions

(No open-register rows were retired as deferred; the items below are sub-decisions the
sign-off explicitly deferred, each with its trigger and arbiter.)

- E4-EXT | E4 skill extension (planning:prd durable-output pitch mode vs a design-handoff
  layer) — deferred behind demand evidence; the doc-tier buy-in pattern ships now (S4).
  Arbiter: human, at the recorded-candidate evidence point.
- D28-SCHEMA | Adding a mechanical scrutiny-flag field to the 5-field open-question register
  schema — the resolution-field convention ships now, gate-invisible by design; the schema
  change waits until a consumer needs mechanical reads (M4). Arbiter: that consumer's
  change, via version bump + changelog per constraint 11.
- EVAL-CAND | Behavioral eval candidates (D5, D7, D11, D17b, D34-residue) — doc lines now;
  promotion to standing skill instructions only on observed-stumble evidence per the
  evidence-gated-additions rule (PLUGIN-PHILOSOPHY:699-711). Arbiter: that rule.
- Q11-FLIP | Flipping tweak-likelihood ordering from documented-default to requestable mode
  in further consumers — deferred to own-usage evidence (interview Q11 residue).
- E1-REG | A convention-registry row for the deviation-log — retracted as premature (M3);
  fires the moment a second plugin reads DEVIATIONS.md (recorded trigger, C5).

## Plan

Written by /planning:plan on 2026-09-01, executing the signed contract (./signoff-sheet.md
rev 2 + this Brief). The delta roster, wave mapping, and definition of done are locked
decisions; these phases sequence their execution, they do not relitigate them.

Standards grounding: no standards index exists in this repo (`.claude/` carries rules, not
an index); the plan is grounded directly in AGENTS.md (affected-tests contract),
docs/PLUGIN-PHILOSOPHY.md (convention registry :591-631, instruction economy :681-718,
two-lane posture :245-286), docs/MIGRATION-PLAYBOOK.md (per-plugin version bump + CHANGELOG
delivery), .claude/rules/vendor-docs-are-not-style.md, and
plugins/knowledge/reference/citation-shape.md — all read this session.

### G-block placements (durable copy; source: round-3 audit merge, confirmed C1)

All are doc-tier placements consumed by Phases 1-2. G1 map/territory: cite-only in F1,
never house vocabulary. G2 over/under-specify diagnostic: F1 doc line, skill edit deferred.
G3 disclose-starting-point primer: F1 pattern-catalog entry. G4 cost framing: F1 intro
rationale line. G5 long-horizon failure diagnostic: F1 doc line, debugging edit deferred.
G6 interactivity scope note: sequencing is chat-portable, artifact optional. G7
fresh-session-per-phase: corroboration, F1 cite only. G8 stay-in-the-loop criterion: quoted
in F1 caution section. G9 density rubric: F1 when-HTML section. G10 ~100-line ceiling: F1,
labeled practitioner anecdote. G11 sharing argument: one F1 line (satisfied by the Artifact
tool). G12 throwaway-editor doctrine: F1 caution section beside the codification warning.
G13 HTML-diff noise: F1 scoping rule (HTML for ephemeral/published outputs, never
version-controlled instruction surfaces). G14 design-system/PR-explainer/report-HTML
options: F1 pattern entries, skill edits deferred. G15 workflow shape: covered by the
five-pass workflow section. G16 named-expert anecdotes: dropped from all graduated
artifacts.

### Phase 1: F1 reference doc — docs/FINDING-YOUR-UNKNOWNS.md [TODO]

Create the graduated reference doc following the top-level precedent shape (H1 →
`## Contents` anchor TOC → charter paragraph → H2 sections). Content contract (signed
Part E + G-block):

- Header: provenance + the C6 permission basis (short attributed verbatim excerpts from
  the named author's public posts under fair-quotation practice, no license claimed, bulk
  reproduction avoided) + the quoting-posture line (quotes stay byte-verbatim; S6/M1) +
  the citation shape stated locally (URL + ISO retrieval date + sha256 over snapshot
  bytes) rather than path-citing the plugin-private shape doc (public-surface rule).
- Unknowns taxonomy + lifecycle: the quadrants, D1's four finding types, G4 cost-framing
  rationale, G2/G5 diagnostic doc lines, G1 map/territory as citation only.
- Five-pass sequencing workflow section (Q7 home) + G6 interactivity note + G7 cite +
  G15 coverage.
- Prompt-pattern catalog (Q9 home): G3 primer entry, G14 pattern entries, one canonical
  invocation line per owning skill.
- Reply-affordance convention + export-button rule: the owner sections for both registry
  rows, each naming its conformance surface verbatim ("conformance = the template blocks
  in prototype:explore-directions (D21/D22) and prototype:pressure-test (D24)").
- When-HTML taxonomy: G9 density rubric, G10 ceiling (labeled practitioner anecdote),
  G11 sharing line, G13 scoping rule, the HTML-scoping rule.
- Buy-in pattern (S4) + E5 objection-evidence checklist, citing Rust RFC / Oxide RFD /
  Amazon PR-FAQ + corpus.
- Caution section: the author's anti-premature-codification warning quoted verbatim with
  citation stamp (Brief constraint 2), G8 stay-in-the-loop criterion, G12
  throwaway-editor doctrine.
- Behavioral heuristics as doc lines, each labeled as an eval candidate awaiting
  observed-stumble evidence: D5 observed-fact evidence bar, D7/D11 disconnected-work
  heuristic/recipe, D17b non-obvious-behavior keying, D34-residue collapse self-check.
- Q11/D31 reconciliation line (presentation ordering is already planning:plan's
  documented default).
- If the doc cites x.com URLs, extend lychee.toml excludes for them (authorized by C6).

**Sanity Check:** `test -f docs/FINDING-YOUR-UNKNOWNS.md`; `grep -c '^## ' docs/FINDING-YOUR-UNKNOWNS.md` ≥ 7;
`grep -q 'retrieved 2026' docs/FINDING-YOUR-UNKNOWNS.md` (citation stamps present);
`grep -qi 'fair-quotation\|fair quotation' docs/FINDING-YOUR-UNKNOWNS.md`;
`scripts/affected-tests.sh --run` green (hygiene lane: markdownlint, typos, lychee).

### Phase 2: Governance placements — registry, glossary, ctx-eng sequencing [TODO]

- docs/PLUGIN-PHILOSOPHY.md convention registry: add exactly 2 names-and-points rows
  (reply-affordance → the F1 doc's owner section; export-button → same). No restating in
  the registry; conformance surfaces live in the owner sections (Phase 1).
- docs/GLOSSARY.md via the /domain-driven-design:curate-language disposition procedure:
  add the unknowns-quadrant vocabulary + D1's four finding types with "Avoid:" lines and
  a dated Provenance entry; map/territory deliberately NOT added (G1 cite-only).
- docs/topics/context-engineering-claude-5/PLAN.md: add "Open, new" bullets under
  `## Open questions` recording F2's three candidates (skill-quality genericness check;
  audit-instructions I29 widening; claude-memory /doctor cross-ref against its existing
  /doctor contract section) and one line noting Phase 10's sweep re-inventories current
  state (recorded counts stale) and rebases over this topic's landed waves. NO phase
  heading/tag renames in that file (D37 / Part G rule 4).

**Sanity Check:** `grep -c 'FINDING-YOUR-UNKNOWNS' docs/PLUGIN-PHILOSOPHY.md` = 2;
`grep -q 'unknown' docs/GLOSSARY.md`; `grep -c 'Open, new' docs/topics/context-engineering-claude-5/PLAN.md`
increased by ≥3; `git diff docs/topics/context-engineering-claude-5/PLAN.md | grep -c '^[-].*### Phase'` = 0
(no phase headings touched).

### Phase 3: discovery plugin — blindspot contract deltas [TODO]

plugins/discovery/skills/blindspot/SKILL.md: D1 typed finding taxonomy in the output
contract; D4 scan-scope disclosure line (POLICY). Extend evals/evals.json expectations for
both new contract lines in this same commit. plugins/discovery/.claude-plugin/plugin.json
version bump + CHANGELOG.md entry.

**Sanity Check:** grep for the taxonomy + disclosure lines in blindspot SKILL.md;
`jq '.evals[].expectations | length' plugins/discovery/skills/blindspot/evals/evals.json`
shows growth vs HEAD; `git diff HEAD --name-only` includes discovery plugin.json + CHANGELOG;
`scripts/affected-tests.sh --run` green.

### Phase 4: education plugin — explain + quiz-me contract deltas [TODO]

explain SKILL.md: D12 vocabulary ladder; D14 success condition scoped to original-ask
invocations. quiz-me SKILL.md: D16 source-anchor + on-miss routing; D17a diff-sourced
question authoring; F4 fresh-context answer-key requirement. Same-commit evals extensions
for all five; education plugin version bump + CHANGELOG.

**Sanity Check:** grep each of the five contract lines in its SKILL.md; evals.json
expectation growth in both skills; affected-tests green.

### Phase 5: verification plugin — confirm deltas [TODO]

confirm SKILL.md: D19 "existing behavior this leans on" callout (CONTRACT) + D18
quiz-layer cross-ref doc line (the reroute executed; quiz-me untouched by D18). Same-commit
evals extension for D19; verification plugin version bump + CHANGELOG.

**Sanity Check:** grep both lines in confirm SKILL.md; evals growth; affected-tests green.

### Phase 6: prototype plugin — explore-directions + pressure-test deltas [TODO]

explore-directions SKILL.md: D20 same-data control-variable rule (POLICY); D21 structured
steal/graft capture; D22 machine-legible reply template (shaped as the skill's OWN output
contract, never a consumer-repo format — lane-2 constraint). pressure-test SKILL.md: D24
validation-answer-set shape; D25 fake-data disclosure footnote (POLICY); D26 per-option
named costs. D27 mock-before-wire composition note as a doc line in the pair. Same-commit
evals extensions; prototype plugin version bump + CHANGELOG.

**Sanity Check:** grep the six contract/policy lines + D27 note; evals growth in both
skills; affected-tests green.

### Phase 7: planning plugin — interview/plan/design/brainstorm deltas [TODO]

interview SKILL.md: D28 free-text scrutiny flag as a RESOLUTION-FIELD convention (the
5-field register schema is untouched; gate-invisible by design, limitation recorded in the
skill text). plan SKILL.md: D32 switch condition on alternatives; D33 closing revision
replies; D35 lands-green forward-reference doc line. design SKILL.md: D36 the same
tweak-likelihood presentation ordering plan already documents. brainstorm SKILL.md: D9
brainstorm-practice citation doc line. Same-commit evals extensions for the four contract
rows (D28, D32, D33, D36); planning plugin version bump + CHANGELOG.

**Sanity Check:** grep each delta line; `bash plugins/planning/tests/`'s
check-open-questions suite still green via `scripts/affected-tests.sh --run` (D28 must not
break the register gate); evals growth for interview/plan/design.

### Phase 8: discipline plugin — point-dont-copy W2 deltas [TODO]

point-dont-copy SKILL.md: E7 primitive-to-convention trap item (CONTRACT); E8 canonical
invocation doc line. Same-commit evals extension for E7; discipline plugin version bump +
CHANGELOG.

**Sanity Check:** grep E7/E8 lines; evals growth; affected-tests green.

### Phase 9: Wave 3 — E6 port gate + E1/E2 deviation-log convention [TODO]

Own review moment; lands after all W2 phases.

- E6 (discipline:point-dont-copy): semantics map + stop-and-wait confirmation gate,
  scoped to external-reference ports with the C3 boundary sentence verbatim ("source of
  truth outside this repo's tree: vendored, foreign-language, other-repo"); in-tree
  corrections stay do-it-now. Extends the discipline CHANGELOG entry from Phase 8 (one
  version bump per plugin per PR). Same-commit evals extension.
- E1+E2 (implementation plugin: implement + implement-dispatch): opt-in deviation-log
  convention + fold-back step; the F1 owner section (Phase 1) is the doc home; the
  recorded-trigger note lands where the convention is stated ("the moment a second plugin
  reads DEVIATIONS.md, the registry rule fires" — no registry row now, per C5/M3).
  implementation plugin version bump + CHANGELOG; same-commit evals extension.

**Sanity Check:** grep the boundary sentence verbatim in point-dont-copy SKILL.md; grep
the trigger note in the implementation plugin; both plugins' CHANGELOGs updated;
affected-tests green.

### Phase 10: Close-out — issues, cheat-sheet, acceptance verification, PR [TODO]

- File follow-up GitHub issues (authorized): one for the behavioral eval candidates
  (D5, D7, D11, D17b, D34-residue), one for the E4 skill extension candidate, one for the
  D28 schema-change deferral, one for Q11-FLIP + E1-REG recorded triggers (or fold small
  ones into a single tracking issue — executor's judgment on granularity).
- `node scripts/generate-cheatsheet.mjs --check`; regenerate once if any frontmatter
  changed (descriptions are NOT edited by any delta, so expected clean).
- Acceptance-criterion 1 verification by grep: every D/E/F/G row id from the sheet
  resolves to a diff hunk or a recorded disposition line; write the sweep result into this
  PLAN under a dated note.
- Full `scripts/affected-tests.sh --run` green on the branch head.
- Push and open the ONE pull request (explicitly requested), body mapping commits to
  waves and citing ./signoff-sheet.md.

**Sanity Check:** `node scripts/generate-cheatsheet.mjs --check` exit 0;
`scripts/affected-tests.sh --run` exit 0; issue URLs recorded in this PLAN; PR URL
recorded; the criterion-1 grep sweep output pasted as a dated note with zero unaccounted
rows.

## Blast radius

MEDIUM-HIGH. Six plugins' skill contracts change in one PR plus two governance docs and a
mid-flight sibling topic's PLAN. Mitigations: every delta is additive prose (no schema,
no executable surface); the parsed schemas in reach are explicitly frozen (Part G rule 4);
per-phase gates run before each commit; the sibling-topic edit is bullets-only.

## Stress-test summary

The execution shape this plan sequences was already adversarially tested this session
before sign-off: /planning:devils-advocate (1 CRITICAL / 4 HIGH / 6 MEDIUM / 4 LOW, all
folded), then two independent fresh-context Fable validators over the sign-off sheet
(amendments folded as rev 2). Step 3's fresh-context plan-reviewer ran over THIS phase
plan; confirmed findings fixed before execution (see dated note below if any).

## Execution shape

Fully sequential, all main-session, phases 1→10 in order (2-8 are order-independent among
themselves but run sequentially anyway; commits are serial on one branch). Basis for
main-session routing: the repo's on-demand convention surfaces (AGENTS.md table) do not
auto-load inside subagents; every phase is judgment-heavy house-style contract writing;
token budget is ample. Sub-agents are used only for fresh-context REVIEW (Step 3 reviewer;
any fresh-eyes checkpoint the executor requests), never for authoring. Sequential fallback
is the shape itself — no parallel orchestration to fall back from.

| Phase | Surface | Basis |
|---|---|---|
| 1-10 | main session | convention surfaces + house style live in main context; serial commits on one branch |
| Step-3 reviewer | fresh sub-agent | mandatory fresh-context stress-test |

## Open questions

None blocking — every decision is signed (./signoff-sheet.md). Deferred items live in the
Brief's Deferred questions with triggers and arbiters.

## Handoff to implementation

### User-approval gates

None remaining: the operator signed the full decision surface (".confirm all") and
explicitly directed all execution into this session, one branch
(claude/reading-feedback-j4sg96), one PR. Any mid-flight pivot that would change an
acceptance criterion still stops and asks.

### Execution shape ([EXEC-SHAPE] tagged)

Decisions made (gate-passed):

| Decision | What it changes in the plan | Basis (evidence) |
|---|---|---|
| [EXEC-SHAPE] F1 doc path = `docs/FINDING-YOUR-UNKNOWNS.md` | Phase 1 target file | SCREAMING-KEBAB at docs/ root is the read precedent for durable cross-cutting references (docs/ inventory read this session); "name at plan time" was delegated by Part E |
| [EXEC-SHAPE] Per-plugin DOC rows (D9, D18, D27, D35, E8) ride their plugin's W2 commit instead of a separate W1 commit | Phases 3-8 contents | MIGRATION-PLAYBOOK: version bump + CHANGELOG is per plugin; folding avoids two bumps per plugin in one PR; wave intent (review structure) is preserved by commit ordering |
| [EXEC-SHAPE] Sequential main-session execution, no parallel fan-out | Execution shape | Convention surfaces don't auto-load in subagents (AGENTS.md); serial commits on one branch; judgment-heavy prose work |
| [EXEC-SHAPE] Registry rows point at the F1 doc as owner (form-2: repo file) | Phase 2 | Registry precedent allows repo-file owners; Part E assigns ownership of both conventions to the F1 doc |
| [EXEC-SHAPE] Deferred/eval-candidate tracking as GitHub issues, granularity at executor's judgment | Phase 10 | Operator: "Its OK if we file issues" |

### Mechanical work

- One commit per phase (Phases 1-2 may merge into one docs commit if small; never split a
  plugin's bump across commits). Commit messages via `git commit -F - --cleanup=verbatim`
  heredoc with the session's attribution footer.
- Per-commit verification: the phase's Sanity Check plus `scripts/affected-tests.sh --run`.
- Push with `git push -u origin claude/reading-feedback-j4sg96` (retry with backoff on
  network failure only).
- PLAN.md phase tags advance `[TODO]` → `[DOING]` → `[DONE]` in the same commit as the
  phase's changes.
