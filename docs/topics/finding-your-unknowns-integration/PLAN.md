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

(unfilled — /planning:plan territory)
