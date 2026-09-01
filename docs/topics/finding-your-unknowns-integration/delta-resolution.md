# Delta resolution — conditional verdicts resolved against grader evidence

Committed copy of the session's delta wording record (originally a work-slice artifact);
the row wording here is what the wave phases implement. Row classifications and wave
assignments were finalized in ./signoff-sheet.md Part D, which supersedes the Status
column below where they differ (e.g. D5/D34 reclassed behavioral-tier, D13 dropped).

2026-09-01. Inputs: six grader reports in evidence/ (file:line evidence there), the
round-1/2 interview locks, corpus-inventory.md. Every row cites its grader. Statuses:
DELTA (change to make), CORROBORATION (already present; optionally cite), NO-CHANGE
(present and stronger than corpus), REROUTE (corpus aimed at wrong home), RETURN
(genuine fork back to human/audit). All DELTA rows are subject to PLUGIN-PHILOSOPHY
"evidence-gated additions": each lands as a sourced, corpus-cited contract line with
the gate acknowledged, or waits for observed-stumble evidence per the audit's call.

## D-block: V2 technique deltas

| ID | Target | Change | Status | Grader |
|---|---|---|---|---|
| D1 | discovery:blindspot | typed finding taxonomy (Landmine/History/Convention/Missing-concept) as output contract | DELTA | blindspot-brainstorm A1 |
| D2 | discovery:blindspot | per-finding prompt-fix | CORROBORATION (present SKILL.md:59) | A2 |
| D3 | discovery:blindspot | fold-step: add explicit human confirm-before-final checkpoint | DELTA (partial today) | A3 |
| D4 | discovery:blindspot | output requires scan-scope disclosure line | DELTA (partial) | A4 |
| D5 | planning:brainstorm | tighten per-option evidence to observed-fact (falsifiable), not just path | DELTA (partial) | B5 |
| D6 | planning:brainstorm | cheapest-to-ambitious ordering | CORROBORATION | B6 |
| D7 | planning:brainstorm | named already-built-but-disconnected scan heuristic (dead imports, dark flags, unread tables) | DELTA (partial) | B7 |
| D8 | planning:brainstorm | structured closing pick | CORROBORATION | B8 |
| D9 | planning:brainstorm | session-start-brainstorm citable rationale line (Q8 lock: only-if-absent; absent) | DELTA (one line) | B9 |
| D10 | improvement:find | corpus S/M/L/XL axis | NO-CHANGE (WSJF+size stronger; adopting would regress) | C10 |
| D11 | improvement:find | disconnected-work recipe file (like hotspots.md) | DELTA (optional, small) | C11 |
| D12 | education:explain | vocabulary ladder (term + definition + modeled "say ->" sentence) | DELTA | edu A1 |
| D13 | education:explain | payoff-prompts closing (before/after prompt contrast) | DELTA | A2 |
| D14 | education:explain | success condition: "user's next prompt names what they mean" | DELTA | A4 |
| D15 | education:explain | three-tier restructure | NO-CHANGE (corpus itself marks hypothesis unvalidated; existing altitude tiers stay) | A3 |
| D16 | education:quiz-me | per-question source-anchor + on-miss routing to the skimmed section | DELTA | B6 |
| D17 | education:quiz-me | diff-sourced question authoring keyed to non-obvious behaviors | DELTA (partial+absent merged) | B7+B9 |
| D18 | quiz-as-merge-gate | REROUTE: quiz-me disclaims merge-gating twice by design; verification:confirm owns the PR gate (SKILL.md:119). Any merge-gate framing lands as a confirm cross-ref, never a second gate | REROUTE | edu B8xC11 |
| D19 | verification:confirm | explicit "existing behavior this leans on" out-of-diff coupling callout | DELTA (partial today) | C10 |
| D20 | prototype:explore-directions | same-data control-variable rule for mockup substrate | DELTA (partial) | proto A1 |
| D21 | prototype:explore-directions | structured steal/graft capture at single-decision granularity | DELTA (partial) | A3 |
| D22 | prototype:explore-directions | machine-legible assembled-reply template (direction/steal/skip/next-target) | DELTA | A4 |
| D23 | prototype:explore-directions | direction count | NO-CHANGE (default 3 cap 5 beats corpus's fixed 4) | A5 |
| D24 | prototype:pressure-test | validation-answer-set output shape (bounded fillable forced-choice answers) | DELTA | B6+B7 |
| D25 | prototype:pressure-test | fake-data/no-real-wiring disclosure footnote (non-dev audience risk) | DELTA (high value) | B8 |
| D26 | prototype:pressure-test | per-option named costs on forced-choice questions | DELTA | B9 |
| D27 | prototype pair | "mock before you wire" named ordering note in composition table | DELTA (small) | B11 |
| D28 | planning:interview | flag free-text answers for downstream scrutiny | DELTA (small) | plan-grader 2 |
| D29 | planning:interview | decisions-table / assembler | NO-CHANGE (register+arbiter cover it; Brief prose is by design) | 3+4 |
| D30 | planning:questionnaire | none | NO-CHANGE (intentional non-adopter: "interview the send, not the subject") | 5 |
| D31 | planning:plan | tweak-likelihood ordering | CORROBORATION (knob already at SKILL.md:223; Q11's "mode" is status quo) | 6+7 |
| D32 | planning:plan | alternatives carry a one-line switch condition | DELTA (partial) | 8 |
| D33 | planning:plan | closing pre-drafted revision replies tied to flagged decisions | DELTA | 9 |
| D34 | planning:plan | self-check before collapsing mechanical sections | DELTA (partial) | 10 |
| D35 | planning:plan | forward-reference implement's lands-green guarantee from Sanity Check | DELTA (one line) | 11 |
| D36 | planning:design | mirror plan's tweak-likelihood knob in Phase-5 discussion rounds | DELTA | 13 |
| D37 | PLAN.md schema | constraint: never rename `### Phase N` heading/tag vocabulary without version bump; block reordering is safe | CONSTRAINT (fact) | 12 |

## E-block: V3/V4 deltas

| ID | Target | Change | Status | Grader |
|---|---|---|---|---|
| E1 | implement pipeline | extend deviation-log convention (taxonomy: plan-confirmed/discovery/deviation/human-decision; plan-said/found/chosen fields; conservative default; blocking markers) from autonomous+Moderate to the interactive path | DELTA (the V3 headline) | port-impl 5+7 |
| E2 | implement Step 5 | required fold-back: read DEVIATIONS.md, emit plan-amendment bullets | DELTA | 6 |
| E3 | session-flow retro/handoff | live-vs-posthoc | NO-CHANGE (complementary by design; E1/E2 close the gap at the right home) | 8+9 |
| E4 | buy-in doc home | design-handoff has 0/4 persuasion elements; prd ships an HTML pitch view (closest precedent); visualize is static (demo routes via playwright/run) | RETURN (fork: extend prd pitch view vs. extend design-handoff vs. new thin skill slot) | 10+11+12 |
| E5 | buy-in components | standalone objection-evidence checklist (question+answer+evidence citation) | DELTA (home follows E4) | corpus f7e96d2a |
| E6 | discipline:point-dont-copy | externalized semantics-map artifact + confirmation gate for EXTERNAL-REFERENCE PORTS ONLY (in-tree corrector doctrine explicitly forbids stop-and-wait; scoping avoids the reversal) | DELTA scoped + RETURN flag (audit must confirm the scoping is clean) | 1+2 |
| E7 | discipline:point-dont-copy | trap check: source primitive with no target analogue -> name the carrying convention | DELTA | 3 |
| E8 | discipline:point-dont-copy | canonical invocation example line | DELTA (one line) | 4 |

## F-block: V5/V6 + reference doc

| ID | Target | Change | Status | Grader |
|---|---|---|---|---|
| F1 | graduated reference doc | new docs/ reference: unknowns taxonomy + lifecycle + pattern catalog + reply-affordance convention + export-button rule + 9-category when-HTML taxonomy + the skill-codification warning quoted; citations per plugins/knowledge/reference/citation-shape.md | DELTA (the Q7/Q9/Q10 vehicle; artifact-design/capabilities are session built-ins, not repo files, so conventions land here) | gov 10-12 |
| F2 | V6 routing | ALL context-engineering deltas route into docs/topics/context-engineering-claude-5/ open phases (article already decomposed, corroborated, gated; audit-instructions I6/I15 already cite it) | REROUTE (supersedes V6 entries 2,3; genericness check and I29-widening and /doctor cross-ref become candidate inputs to that topic, not this one) | gov 1-9 + surprise |
| F3 | claude-memory:audit | gotcha-vs-obvious heuristic | CORROBORATION (C2 Deletion Test + C5) | gov 6 |
| F4 | quiz-me fresh-eyes tension | quiz author self-grades in biased context vs. philosophy's fresh-eyes doctrine | RETURN (design question beyond corpus scope; surfaced to human) | edu surprise 2 |

## Standing constraints carried into every delta

1. PLUGIN-PHILOSOPHY evidence-gated additions (:699-711): corpus-anticipated is not
   observed-stumble; each delta lands citing the corpus as source AND acknowledging the
   gate, with the audit deciding per-delta whether the gate demands deferral.
2. One-mechanism-per-concern (:678-679): D18 reroute is the enforcement example.
3. MIGRATION-PLAYBOOK version pinning: D37; any parsed-schema touch needs changelog.
4. Two-lane convention posture: no hardcoded decision-record formats or literal
   path/flag templates in conventions (proto grader note).
