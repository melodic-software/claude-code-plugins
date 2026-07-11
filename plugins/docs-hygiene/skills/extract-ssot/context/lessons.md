---
type: lessons-empirical
format: append-only
source: /extract-ssot batch executions
schema-version: 1
---

# Empirical lessons — `/extract-ssot`

Append-only record of patterns observed during real `/extract-ssot` runs. Distinct from `decision-framework.md` (a-priori 6+5 gate) and `anti-patterns.md` (failure-mode taxonomy with mitigations) — this file captures **empirical observations** from running the skill on real candidates and learning what the survey heuristic over-counts, what categorical-shape signals indicate distinct concerns, and what extraction shapes succeed vs refuse.

Lessons 1-11 were seeded from batch runs in the repository where this skill was developed (sources below are genericized). Consuming repositories append their own lessons as batches run.

Each lesson has a stable identifier (`Lesson N`) so anti-patterns + decision-framework + verify gates can cite by number. Appending a new lesson means adding `## Lesson N+1` at the bottom — never re-number.

## How this file is consumed

- `verify` action (`actions/verify.md`): the Tier 0 gates implement these lessons as ordered checks
- `anti-patterns.md` patterns #11/#12/#13: Lessons 8, 6, 9 are codified as named anti-patterns / positive patterns
- `decision-framework.md` "Pre-extraction Tier 0 checklist": lessons surfaced as a-priori discipline AFTER the 6-test gate
- Manual review: a human surveying a candidate cluster reads these to short-circuit obvious refusals

This file is PRIVATE surface — external consumers don't cite `lessons.md "Lesson N"` directly. They invoke `/extract-ssot verify` or read the codified anti-pattern. Keeps audience boundaries clean.

## Lesson 1: Discriminating-phrase grep beats keyword density

**Observation.** Survey heuristics that count "any mention of <keyword>" (e.g. `subagent`, `rate limit`, `worktree`) systematically over-count duplication. A keyword appearing in 21 files does NOT imply 21 reproductions of the same cluster — most are 1-line teaching mentions, not full reproductions.

**Trigger.** Pre-extraction surveys that count via keyword density.

**Mitigation.** Identify a verbatim phrase ≥ 8 words that uniquely characterizes the cluster body. Grep for that. Count distinct full reproductions, NOT teaching mentions.

**Source.** A 13-candidate batch — 10 REFUSED in part because the keyword-density survey over-counted by 4-5×. Examples: workflow-chain prose (claimed 18+ instances; 1 full reproduction in the canonical), a resume-protocol cluster (claimed 6 instances; 1 full reproduction), an environment-detection cluster (claimed 21 mentions; 2 distinct full reproductions).

**Encoded in.** `verify` action Gate 1; `decision-framework.md` Pre-extraction Tier 0 checklist; `anti-patterns.md` #7 (premature extraction) supplement.

## Lesson 2: Pre-existing canonical citation = no extraction work remains

**Observation.** When call sites ALREADY cite the canonical SSOT (e.g. `per X.md "Y"`), the SSOT-extraction work is already done. The candidate appears in the survey because the keyword surfaces, not because new extraction is needed.

**Trigger.** Surveys produced from `identify` runs against repos with mature SSOT layers.

**Mitigation.** For each call site, grep ~10 lines surrounding for `per <some>.md "<heading>"` patterns. If ALL sites already cite canonical → REFUSE-already-cites-canonical.

**Source.** Same batch — a merge-policy candidate (4 sites, all citing the canonical with bidirectional links); a budget-math candidate (5 sites, all citing the owning rule file); an auth-degradation-chain candidate (2 of 3 sites already citing the owning doc by heading).

**Encoded in.** `verify` action Gate 2.

## Lesson 3: Off-by-one step count signals distinct concerns

**Observation.** When two clusters look superficially similar but differ in step count or variant shape, they're typically NOT the same cluster — they're distinct concerns the survey conflated.

**Trigger.** Multi-step or numbered-list clusters that "look the same" by keyword overlap.

**Mitigation.** Compare step counts, step names, and ordering across instances. If counts diverge non-trivially, these are different concerns; refuse extraction; flag for a narrower discriminating-phrase grep.

**Source.** Same batch — a claimed "7-step lifecycle" candidate; the canonical lifecycle rule was 6-step. The survey's "7" came from a sibling rule documenting a different lifecycle entirely (naming gates, not the state machine). Off-by-one was the diagnostic.

**Encoded in.** `verify` action Gate 5.

## Lesson 4: Path 1 / Path 2 bifurcation is intentional — preserve

**Observation.** Some sibling files document INTENTIONAL bifurcation — two related but distinct lifecycles, two related but distinct workflows. They look like duplicates to a naive sweep but collapsing them loses semantic distinction.

**Trigger.** A cluster spans 2 sibling files in the same rules directory with similar headings but distinct subject names.

**Mitigation.** Read both in full. If one says "Path 1" / "Path 2", or names two distinct flows in its own intro, REFUSE extraction; the bifurcation is intentional. Document why preservation matters in the working notes.

**Source.** Same batch — a branch-naming rule's Path 1 (rename lifecycle) ↔ Path 2 (post-merge reuse lifecycle) pair. The survey conflated them with a separate 6-step lifecycle canonical; preservation was correct.

**Encoded in.** `verify` action Gate 5 adjacent rationale; `anti-patterns.md` #6 (wrong abstraction) supplement.

## Lesson 5: LOW-ROI threshold — single-sentence + low-drift = inline

**Observation.** Some clusters technically pass Rule of Three (3+ instances) and pass categorical-shape (same single sentence verbatim) but the cluster body is so small + stable that abstraction maintenance dominates the duplication cost.

**Trigger.** Cluster body ≤ 1 short paragraph (~80 words / single sentence) AND drift rate ≤ 1×/year.

**Mitigation.** Refuse extraction. Inline at each call site. Document the LOW-ROI verdict + a recheck trigger ("if drift increases").

**Source.** Same batch — a squash-merge-derives-commit-from-PR-title fact (3 instances of a single sentence describing vendor product behavior with near-zero drift); a second candidate at n=2 (below Rule of Three, but the LOW-ROI argument would have applied had it passed).

**Encoded in.** `verify` action Gate 6; `decision-framework.md` keep-inline test E supplement.

## Lesson 6: Primary-source citation gate — don't replace primary URLs with internal SSOT

**Observation.** When all call sites cite a primary-source URL (vendor doc, RFC, language spec) directly, an internal SSOT cannot improve on that. Internal SSOT is for repeated *internal-vocabulary* claims, not re-statements of primary facts.

**Trigger.** Call sites contain canonical URLs from `code.claude.com`, `platform.claude.com`, `anthropic.com`, `tools.ietf.org/rfc`, `learn.microsoft.com`, etc.

**Mitigation.** REFUSE-primary-source-citation-gate. Surface a side note that the URL should be re-verified for resolution + suggest documenting the primary-source dependency at the rule top.

**Source.** Same batch — a metric-formula candidate: 3/3 sites cited the vendor doc URL directly; the verbatim fraction was 0% because each site stated the formula differently per its concern context.

**Encoded in.** `verify` action Gate 3; `anti-patterns.md` #12 (primary-source citation gate).

## Lesson 7: Concern-driven drift is intentional

**Observation.** Multiple sites can carry the "same fact" with different surface phrasings because each site addresses a different concern (schema field shape vs framing prose vs query pipeline operator). The drift is signal, not noise — collapsing forces wrong-abstraction.

**Trigger.** Cluster instances differ in framing but share an underlying fact; consumers serve distinct audiences (schema validators vs cost-attribution writers vs query authors).

**Mitigation.** REFUSE single-unit extraction. Preserve each consumer's framing inline. If centralization is desired, extract at MOST a 1-line "prescribed upstream" statement + URL, NOT the multi-form derivation.

**Source.** Same batch — the metric-formula candidate again: 3 instances each in a distinct shape (a schema row with `× 100` integer percent, a query with full field names, ratio prose with short field names; mathematically distinct re aggregation: single-sample vs sum-aggregation).

**Encoded in.** `decision-framework.md` keep-inline test D (instances differ in non-trivial ways) supplement; `anti-patterns.md` #6 (wrong abstraction) supplement.

## Lesson 8: Source-of-truth bifurcation across tiers is legitimate

**Observation.** A concept can originate in the top-tier always-loaded instruction file (`CLAUDE.md`/`AGENTS.md`) AND be aggregated in a scoped rule file (deep-disclosure for hook/skill/script authors). Both are first-class canonicals. Each serves a distinct audience. Forcing the instruction file to cite the rule creates a citation cycle (instruction file → rule → instruction file).

**Trigger.** A cluster originates in CLAUDE.md/AGENTS.md AND is also documented in a rule file with deeper detail.

**Mitigation.** REFUSE-source-of-truth-bifurcation. Document both canonicals + their respective audiences in the rule file if not already explicit.

**Source.** Same batch — an environment-detection cluster: the instruction file carried the session-facing sentinels for the full-session audience; a scoped rule aggregated the env-var matrix for hook/script authors who need the detection ladder.

**Encoded in.** `verify` action Gate 4; `anti-patterns.md` #11 (source-of-truth bifurcation).

## Lesson 9: Shape C dedup-by-deletion (positive pattern)

**Observation.** When the SSOT already exists and consumers paraphrase it, the right action is NOT extraction (the SSOT is already there) — it's DELETION of the redundant paraphrasers in consumer files. Keep load-bearing directives (e.g. `Read X.md first`); delete redundant tail prose.

**Trigger.** The cluster body in consumers reads as a TL;DR of an existing canonical SSOT, not as inlined content.

**Mitigation.** Shape C action: delete the redundant tails from each consumer; preserve the load-bearing directive. The SSOT is unchanged. No new file; no migration sweep needed (just deletion). Per-consumer deltas (intentional variations) preserved inline.

**Source.** Same batch — a bootstrap-preamble candidate: a dozen automation prompts carried the same descriptor tail; a shared doc was already canonical with the full content; deletion was correct vs. extraction-and-citation.

**Encoded in.** `anti-patterns.md` #13 (Shape C dedup-by-deletion — positive pattern).

## Lesson 10: Identify subagent over-counts ~95% on broad surveys without verbatim-block discrimination

**Observation.** When `/extract-ssot identify` runs in exhaustive mode (read-only subagent over 30+ heuristics), the subagent's roster routinely flags 60+ candidates with a ~95% false-positive rate at Tier 0 verify. Failure modes:

1. **Section-header presence** counted as duplicate (e.g. 18 skills have a `## What this skill does NOT do` header; bodies are unique per skill — template, not duplication)
2. **Concept mention** counted as block reproduction (a file mentions a verification tier once → flagged as a duplicate of the full tier-ladder definition)
3. **Correct citation to SSOT** counted as "still inlined" (a `per X.md "Y"` token treated as inline duplication)
4. **Language-native dedup** flagged as duplication (bash `source utils.sh` in 34 files counted as code duplication; that IS the dedup mechanism)
5. **Per-prompt/per-skill unique lists** confused with shared boilerplate (an exclusion list per prompt has UNIQUE scope-specific entries; template structure ≠ content duplication)

The subagent ALSO under-counts in some cases — a verbatim 5-place reproduction of a dependency-direction rule was flagged as 2 instances. Heuristic asymmetry: keyword-density inflates structural matches, deflates verbatim-rule clusters.

**Trigger.** Bare-subagent survey dispatch with broad heuristics and no Tier 0 verification at identify-time.

**Mitigation.**

1. The identify prompt MUST require a verbatim-body excerpt per cluster + reproduction-count via discriminating-phrase grep
2. The identify prompt MUST distinguish: (a) verbatim block reproduction, (b) section-header presence, (c) concept mention, (d) correct citation, (e) per-instance unique data with shared template. Only (a) and (e)+(framing-only) count
3. Identify scope MUST be `git ls-files` only — exclude gitignored, untracked, and ephemeral/vendored/fixture content dirs
4. Per-language native dedup (bash `source`, Python `import`, JSON `$ref`, MSBuild `<Import>`) is already-extracted; flag as out-of-scope, not as a candidate
5. The `verify` action becomes a HARD GATE for batches ≥5 candidates (not an optional pre-filter) — refuse-fast before any plan/execute

**Source.** An exhaustive-mode session — the survey subagent produced a 60-candidate roster. Tier 0 manual verify on the top 15 candidates yielded 1 PROCEED (a verbatim 5-instance dependency-direction rule), 14 REFUSE. Spot checks on the remaining ~45 candidates confirmed the pattern (header-only matches, concept mentions, SSOT-cites, language-native dedup). Overall ~95% FP rate. Cost: ~30+ Tier 0 grep calls to disprove the subagent synthesis.

**Encoded in.** `actions/identify.md` prompt template (Discrimination rules + scope hardening); `actions/batch.md` Step 2 (verify-as-hard-gate for size ≥5).

## Lesson 11: Stability + reader-burden combined test for semantic-equivalent paraphrase

**Observation.** Verbatim-only Rule of Three misses semantic-equivalent paraphrases — the same canonical truth restated in different wording across N files. User feedback: *"Anything that is really a maintenance burden that would cause more than one place to update if changed... we want one source of truth and everything else points to that"*. A verbatim-only test under-counts semantic dupes; a pure semantic-similarity test over-counts coincidental similarity.

**Trigger.** A cluster surfaces N≥3 instances that share canonical meaning but differ in surface phrasing.

**Mitigation.** Combined test — extract iff EITHER:

- **Stability test:** changing the canonical truth would force updates in 3+ places in lockstep (maintenance burden), OR
- **Reader-burden test:** a reader trying to understand the rule cannot tell which instance is canonical (ambiguity)

If only ONE passes, extraction is borderline — run an adversarial-review round. If NEITHER passes, REFUSE-low-roi (coincidental similarity).

**Counter-test (when NOT to extract despite semantic equivalence):**

- Each instance applies the rule to its own domain-specific scope (e.g. planning vs implementation vs testing skills each apply a testing default in their own framing) — keep; this is context-specific application
- A section-header pattern is shared but the bodies are skill-specific data (e.g. "What this skill does NOT do" lists) — keep; this is convention/template
- The SSOT designer EXPLICITLY chose to keep a portion inline (e.g. a shared template that keeps examples per-consumer by design) — respect the architectural decision; surface as a side observation if you disagree

**Source.** A duplication-taxonomy review session. A 5-consumer identical framing template with unique per-consumer examples was considered for extraction and deferred per the architectural intent stated in the SSOT body. A 5-instance verbatim dependency-direction rule was extracted successfully. A "What this does NOT do" candidate was REFUSED — section-header pattern with unique non-goals per skill.

**Encoded in.** `decision-framework.md` 6+5 gate (extends Rule of Three with the combined test); `actions/identify.md` prompt template (distinguishing form (e) per-instance unique data with shared framing).

## Append guidance for future batches

When a future `/extract-ssot batch` execution surfaces a new empirical pattern:

1. **Confirm novelty.** Cross-check the existing lessons. If the new observation is a variant of an existing lesson, expand that lesson's scope rather than adding a new one.
2. **Confirm Tier 0 evidence.** An empirical lesson requires concrete batch references — date + cluster name + outcome. NOT speculation.
3. **Append `## Lesson N+1`** at the end of the file. Schema: name (one-line), Observation, Trigger, Mitigation, Source (date + cluster + outcome), Encoded in (which downstream artifacts cite this lesson).
4. **Cross-reference.** If the lesson should drive a new `verify` gate, anti-pattern, or decision-framework row, append that addition in the same PR.
5. **Cap.** When the file approaches 400 lines, propose a split: archive older lessons to the working notes, retain the most-recent-N + greatest-impact-M in this file. Document the recheck trigger with the split proposal.

## Cross-references

- `decision-framework.md` "Pre-extraction Tier 0 checklist" — codifies lessons as a-priori discipline
- `anti-patterns.md` patterns #11 (Lesson 8), #12 (Lesson 6), #13 (Lesson 9)
- `actions/verify.md` Gates 1, 2, 3, 4, 5, 6 — implementation of Lessons 1, 2, 6, 8, 3+4, 5
- SKILL.md "Evidence discipline" — Tier 0 evidence requirement for new lesson appends
