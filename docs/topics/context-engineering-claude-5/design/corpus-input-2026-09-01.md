# Corpus input — 2026-09-01 (context-engineering-integration sign-off)

A dated input record from the signed-off sibling effort
(`docs/topics/context-engineering-integration/PLAN.md`, commits 6b7cd132..): a byte-verified
two-article corpus pass (the P1 X article this plan absorbed, PLUS the Anthropic
"Effective context engineering for AI agents" engineering post of 2025-09-29, plus nine
linked pages), a fresh unbiased paragraph-grain sweep, bidirectional reconciliation against
this plan's design docs, and two independent validation arms. Operator decision Q15
(2026-09-01): this plan is to be **finished** (phases 8-11), with this note as a mandatory
Phase 10 reconcile input. Each actionable payload below carries (or will carry) a tracker
receipt; this note is the in-plan record, not the disposition.

## Payloads that change execution

1. **P2 was never engaged by this plan** (grep-verified: zero hits for the post title, URL,
   "context rot", or "attention budget" across this slice). The post's mechanism layer
   (attention budget, context rot, altitude calibration, JIT retrieval, compaction/notes/
   sub-agents triad) is net-new corpus context for Phase 8's detector work and Phase 10's
   reconcile. Verified digest slice + coverage ledger live in the sibling effort's record.
2. **I15 boundary reopen candidate (OPINION-tier).** I15's criteria scope conflicts to
   resident-surface pairs by recorded design (its Source block cites the article's
   user-request example). The corpus pass surfaces the third axis — standing instructions vs
   plausible user requests — as a detector candidate for the still-open catalog, contingent
   on a detectability answer (gate-5-style realistic-prompt fixtures over an enumerated
   request population). Reopen, not extension; adjudicate in Phase 8's criteria-edit branch.
3. **design/rerun-contract.md has drifted further** since its 2026-08-12 "shipped contract
   wins" reconciliation banner: the shipped skill has since gained lease/epoch mechanics the
   doc predates. Phase 10's reconcile should re-sync or explicitly re-scope the doc.
4. **official-corroboration.md line 3 wording fix**: the source is a personal X article by
   Anthropic staff (with a claude.com/blog twin), not "a post on Anthropic's Claude blog"
   as one natural reading suggests. The venue characterization was litigated in #2036/#2057
   and the doc's own hedge already limits damage — this is a wording precision fix, tier
   logic unaffected. Note: the blog twin
   (claude.com/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models)
   carries the 80% figure in its description; under criteria.md:153-158 a vendor blog
   corroborates rather than defines, so OPINION-tier treatments stand, now with both
   carriers citable.

## Caveat clusters routed here (execution-adjacent)

- **G-SEC** (guardrail-deletion and memory/notes-poisoning security consequences of the
  unhobbling posture) is filed as its OWN work item (security cost of burial) — recorded
  here only so Phase 8's deletion-recommending checks know the caveat exists.
- The interface-vs-behavior-constraint thesis (G-THESIS) and audience-precondition
  assumptions (G-PRECOND) ride with the sibling effort's corpus apparatus; they inform
  D2-class detector rationale if Phase 8 reaches it.

## Settled facts the phases can rely on (verified against live surfaces 2026-08-31/09-01)

- `/doctor` per commands.md (v2.1.205/206): trims/dedupes/migrates checked-in CLAUDE.md
  guidance into skills; finds unused skills vs context cost. No official surface describes
  skill-content "rightsizing".
- The `#` memory hotkey was REMOVED in v2.0.70 (changelog block, spot-verified).
- Memory tool: all Claude 4+ models, no beta header; context editing: beta; Claude Code
  exposes neither natively (analogues: auto-memory, compaction).
- Claude Code changelog recency anchor for the above: v2.1.252.
