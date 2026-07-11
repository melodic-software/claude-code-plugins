# Anti-patterns guarded

13-pattern taxonomy. Each entry: pattern + symptom + mitigation procedure. SKILL.md cites this file for the full taxonomy; the body lists pattern names only.

Patterns are framed for markdown extraction (the dominant case) but apply to code and config extractions too — citation rot has a code analog (function rename = stale `import`), over-indirection has a code analog (re-export chains), wrong abstraction is the same Sandi Metz failure regardless of language. File-class adaptations are called out per pattern below.

## 1. Citation rot

**Pattern.** Heading rename in the extracted file silently breaks all references. Pure-token grep on the OLD heading text returns matches in caller files; nobody updates them; the agent reads the caller's stale citation and either follows a dead link or hallucinates plausible content matching the old heading name.

**Symptom.** Caller text reads `per X.md "Old Heading"`; X.md no longer has an H3 with that exact text. A `/rename-references` sweep would have caught it.

**Code/config analog.** Function/constant/anchor rename in the SSOT module breaks every `import`, `using`, or `$ref` that pinned the old name. Same failure shape; the mitigation is the same sweep + IDE rename refactor.

**Mitigation.**

1. Cite by EXACT heading text (markdown), exact identifier (code), exact anchor (config) — never by line number or section number
2. After ANY heading/identifier/anchor edit in an SSOT, run `/rename-references` immediately — it sweeps all 10 syntactic forms, not just pure-token grep
3. The SSOT file should include a `## Recheck triggers` section — a rename row triggers the sweep
4. For code: prefer language-aware refactor (IDE / Roslyn / ts-morph) over text grep; combine with `/rename-references` for non-source references (docs, configs)

## 2. Over-indirection

**Pattern.** A.md → B.md → C.md chains. The reader has to follow 2-3 links to assemble meaning. Per-link failure rate compounds.

**Symptom.** A skill body cites a rule file; the rule file cites another rule file for the same domain. Anthropic's "head -100" partial-read failure mode triggers when the chain is deep.

**Code/config analog.** Re-export chains: `module-A` re-exports from `module-B` which re-exports from `module-C`. IDE "go to definition" jumps through layers; refactor breakage cascades. The same one-level-deep rule applies — the call site imports the canonical SSOT directly.

**Mitigation.**

1. Enforce "one level deep" — refuse to ship the extraction if the SSOT itself references another extracted SSOT for the same domain
2. If two SSOT files cover related domains, either merge them OR cite both directly from the caller (one level each)
3. Lint check: grep the extracted SSOT for `\.md "` patterns; warn on >2 references to OTHER `.md` files
4. Code: ban re-export-only modules (`export * from "./other"`); each module owns its own surface

## 3. Leaky abstraction

**Pattern.** The extracted file uses pronouns or references that assume caller context — "the prior step", "as discussed earlier", "this command above", "that flag we mentioned".

**Symptom.** Reading the extracted file in isolation produces nonsense. Joel Spolsky's law applied to docs.

**Code/config analog.** A helper depends on global state the caller happens to set (mutable singleton, ambient context, env var only one caller exports). A config include references variables only the includer happens to define. Same failure shape; the mitigation is to make dependencies explicit (parameters, dependency injection, required-input declaration).

**Mitigation.**

1. Self-test: read the extracted file in isolation and ask "does this make sense without the surrounding context I just came from?"
2. Lint pattern (markdown): detect context-assuming phrases via grep — `prior`, `earlier`, `above`, `previous`, `as mentioned`, `as discussed`, `the X we`, `that step`
3. Code: pure-function preference; explicit parameters over ambient context; document required setup at the import site
4. Config: declared inputs at the include site; no implicit variable inheritance
5. Rewrite to self-contained form OR refuse extraction

## 4. Loss of locality

**Pattern.** The reader has to jump 3+ files to understand intent at the call site. Cite-by-name without inline context strips ALL meaning from the caller.

**Symptom.** Caller text reads `per X.md "Y"` and nothing else. The reader has no idea what Y does or why it matters here.

**Code/config analog.** Bare `import { someThing } from "./util"` with no usage context near the call site, or YAML `<<: *anchor` with no comment naming what the anchor encapsulates. The reader has to chase the import to understand intent.

**Mitigation.**

1. Cite-by-name AND inline 1-line summary at every call site. Template: `per <file>.md "<heading>" — <≤80 char shape description>`
2. The 1-line summary should let a reader skim the caller and understand the SHAPE of the cited rule without clicking through
3. Code: name imports for what they do, not where they live; cluster related imports; brief comment at non-obvious call sites
4. Config: name anchors descriptively (`&dotnet-build-defaults` not `&base`); short comment above the alias if intent isn't obvious
5. Full markdown contract in `citation-form.md`

## 5. Reference resolution failure

**Pattern.** Heading renamed in the SSOT; the agent searches the caller's old citation text against the SSOT, fails to find it, hallucinates plausible content matching the old heading name.

**Symptom.** Same observable as citation rot (#1) but from the AGENT's perspective at read time. The agent confidently produces output as if the citation resolved successfully when it didn't.

**Mitigation.**

1. The SSOT file ships with a `## Stable headings — change requires sweep-references` section listing exact anchor text + dependent call sites
2. Verify before acting: when a citation says `per X.md "Y"`, the agent MUST grep X.md for the literal heading "Y" before acting on assumed content
3. If citation-resolution hallucination becomes measurable, add resolution-time verification tooling (a hook or lint that greps the cited heading on read/write)

## 6. Wrong abstraction (Sandi Metz failure mode)

**Pattern.** The extracted SSOT has 5+ callers, each passing different boolean flags or conditional branches. Params + conditionals proliferating IS the failure signal.

**Symptom.** Caller code reads `/<skill-name> <flag-A> <flag-B> --variant=Q` with each caller using a unique combination. The SSOT body is a switch-statement of `if flag-A then ... else if flag-B then ...`.

**Mitigation.**

1. The `unwind` action implements Metz's 3-step recovery:
   - Re-introduce duplication by inlining the SSOT body back into every caller
   - Within each caller, keep only the subset that caller actually needs
   - Delete unneeded bits per caller
   - Re-isolate genuine duplication and re-extract with corrected shape
2. Record the unwind decision in the working notes (it is a hard-to-reverse call worth documenting)
3. After unwind, re-run the `identify` action; only re-extract if Rule of Three still holds with the corrected shape

## 7. Premature extraction

**Pattern.** Extracting at the first or second instance of perceived duplication. Two prompts do similar (not identical) things; the agent extracts to a "shared helper" before a third instance proves the pattern is real.

**Symptom.** The SSOT has 2 callers; one of them is awkward because the SSOT shape was guessed from one strong example + one weak example.

**Mitigation.**

1. The `identify` action requires evidence of 3+ instances before recommending extraction — Tier 0 grep output captured this turn, not recall
2. Refuse extraction when only 2 instances exist; cite Rule of Three with author attribution (Don Roberts / Fowler)
3. Offer to record a tracking note in the working notes so future-self knows to revisit when the third instance lands

## 8. Self-generated SSOT

**Pattern.** The model authors a skill or rule that the model itself cannot reliably consume. SkillsBench negative finding: self-generated skills provide NO benefit on average; human curation is the only reliable path.

**Symptom.** The SSOT was written end-to-end by an agent without human review at any phase boundary. Eval cases (if any) were also model-authored. Failure rate higher than ad-hoc inline.

**Mitigation.**

1. SSOT output goes through human review — the user stages, commits, and reviews the diff
2. Phase boundaries surface the diff to the user explicitly; never auto-stage/commit/push
3. Eval cases for any new skill MUST be human-reviewed against expected output before declaring done

## 9. Cache invalidation cascade

**Pattern.** Extraction creates a new always-loaded file that gets edited often; downstream sessions' prompt caches invalidate on every edit; token cost rises for every session that loads it.

**Symptom.** Cache-creation token volume rises relative to baseline in usage telemetry; cache hit rate for sessions in the repo drops after the SSOT lands.

**Mitigation.**

1. Decision-framework test #3 (Stable — content changes <1×/quarter) is the up-front gate
2. If the SSOT must be edited frequently, split it: stable categorical bits stay in the SSOT, volatile narrative goes back inline
3. A Recheck-triggers section in the SSOT documents anticipated edit frequency; if it drifts >1×/month, raise it as a side observation

## 10. Encapsulation violation

**Pattern.** A caller references skill internals (`.claude/skills/<X>/scripts/<file>`, `<X>/context/<topic>.md`, `<X>/actions/<name>.md`, `<X>/reference/<file>.md`) instead of the `/X` invocation. Bypasses the skill's public-API contract; ties the caller to internal layout that may move.

**Symptom.** Grep `.claude/skills/[^/]+/(context|actions|reference)` against caller files returns matches. The caller reads file content directly rather than invoking the skill action that uses it.

**Mitigation.**

1. The `execute` action converts external skill-internals refs back to `/X` invocations as part of the work, NOT preserved
2. `scripts/*.sh` is the documented public-API exception — those CAN be cited externally (see `/encapsulation-audit`)
3. If the caller's use case has no public action covering it, surface as a side observation (NOT fix-in-passing) — the skill needs an action added before the caller can route through the public API
4. Detection grep + remediation paths: `/encapsulation-audit`

## 11. Source-of-truth bifurcation (REFUSE trigger)

**Pattern.** A concept legitimately exists at TWO tiers — a top-level always-loaded source (`CLAUDE.md` / `AGENTS.md`) for the every-session audience, AND a deep-disclosure aggregator rule file for hook/skill/script authors who need detection mechanics or implementation detail. Both are first-class canonicals serving distinct audiences. Forcing the instruction file to cite the rule creates a citation cycle.

**Symptom.** A survey claims "N inline reproductions of <fact>" but Tier 0 grep shows 1 reproduction in the instruction file (top-tier canonical) + 1 in a rule file (aggregator) + N-2 single-concern call sites that need only a slice. Forcing single-citation extraction collapses two legitimate canonicals into one.

**Code/config analog.** The same fact lives in a public README (top-tier audience) AND a developer-guide reference doc (deeper audience); collapsing the README to cite the dev-guide breaks the README's stand-alone value for the entry-point audience.

**Mitigation.**

1. The `verify` action Gate 4 detects bifurcation; refuses extraction with `REFUSE-source-of-truth-bifurcation`
2. Document both canonicals + their respective audiences in the rule file if not already explicit
3. Single-concern call sites can still cite either canonical (whichever serves their narrower scope) — keep their narrow-slice usage rather than forcing whole-fact citation
4. **Verbatim source.** `lessons.md` Lesson 8.

## 12. Primary-source citation gate (REFUSE trigger)

**Pattern.** All call sites already cite a primary-source URL directly (vendor doc, RFC, language spec). An internal SSOT cannot improve on a primary URL the consumer already inlines.

**Symptom.** Pre-extraction grep shows every call site contains a primary-source URL within ~5 lines. The verbatim fraction across sites is near 0% because each site states the primary fact in its concern-specific framing.

**Code/config analog.** Code already imports a typed constant from a third-party package's exported API; introducing a wrapper file that re-exports the constant adds indirection without value (the compiler already pins the name).

**Mitigation.**

1. The `verify` action Gate 3 detects primary-URL coverage; refuses with `REFUSE-primary-source-citation-gate`
2. Internal SSOT is for repeated *internal-vocabulary* claims (where there IS no primary source), NOT re-statements of facts the primary publisher owns
3. If centralization is desired anyway, extract at MOST a 1-line "prescribed upstream: <URL>" statement, NOT the multi-form derivation
4. **Recheck trigger:** if the primary URL goes 404, all sites need a fallback; that's the moment to revisit
5. **Verbatim source.** `lessons.md` Lesson 6.

## 13. Shape C — dedup-by-deletion (POSITIVE pattern)

**Pattern (positive — applies when the cluster IS already SSOT-shaped).** When an existing canonical SSOT already documents the full content and consumer files paraphrase that content as a TL;DR, the right action is NOT extraction (it already exists) but DELETION of the redundant paraphrasers. Keep the load-bearing directive (e.g. `Read X.md first`); delete the redundant TL;DR tail prose.

**Symptom.** The cluster body across N consumer files reads as a TL;DR / restatement of an existing canonical's intro paragraph. Consumers cite or reference the canonical but ALSO restate its content nearby. Extraction would be a no-op because the SSOT exists; the redundancy is in the consumers.

**Code/config analog.** A code helper exists; consumers `import` it AND inline a copy of the body "for clarity"; the inline copy is dead weight — delete it, the import is sufficient.

**When to apply.**

- An existing rule file or skill body already serves as the SSOT
- 3+ consumers paraphrase that SSOT's content while ALSO referencing the SSOT by name
- The paraphrase adds zero unique signal (it's strictly a restatement)
- Per-consumer intentional deltas (e.g. prompt-specific phase pointers, custom constraints) are NOT in the redundant body and stay inline

**Mitigation / execution.**

1. The `verify` action Gate 2 (pre-existing canonical citation) is the entry point — if it returns `REFUSE-already-cites-canonical` AND the consumer ALSO has a redundant paraphrase nearby, that's the Shape C signal
2. Run a deletion-only sweep: for each consumer, identify the redundant TL;DR tail; delete; preserve load-bearing directives + per-consumer intentional deltas
3. No new file. No `/rename-references` sweep (no identifier change). Pure dead-text removal
4. **Verbatim source.** `lessons.md` Lesson 9. Canonical example shape: a dozen automation prompts each carried a redundant one-line descriptor tail restating a shared doc that was already canonical with the full content; deleting the tails was correct

**When NOT to apply.**

- The consumer paraphrase carries unique framing (concern-driven drift per Lesson 7) — keep inline
- The "SSOT" is itself just a paraphrase of a primary-source URL (Lesson 6) — don't grow the redundancy
- The consumer is intentionally short-form (1-line teaching mention, not full restatement) — leave as-is per Lesson 1's exclusion

## Cross-references

- `decision-framework.md` — when to extract (avoiding patterns 6-9 up front); "Pre-extraction Tier 0 checklist" formalizes #11/#12/#13
- `citation-form.md` — anti-patterns 1, 4, 5 mitigation contract for markdown call sites; for code/config see SKILL.md "Output type"
- `/encapsulation-audit` — anti-pattern 10 detection + remediation matrix (separate skill)
- `execution-checklist.md` — per-phase sanity checks that catch each anti-pattern
- `lessons.md` — empirical batch-derived patterns; #11 ↔ Lesson 8, #12 ↔ Lesson 6, #13 ↔ Lesson 9
- `actions/verify.md` — refuse-fast gates implementing anti-patterns #11 (Gate 4), #12 (Gate 3), #13 (Gate 2 entry-point); Gates 1/5/6 implement Lessons 1/3+4/5 (informational, not refuse-anti-patterns)
- SKILL.md "Evidence discipline" — verify-before-acting for citation resolution (#5); Tier 0 evidence requirement for the #11/#12/#13 detection greps
- `/rename-references` — the 10-pattern sweep that catches #1, #4, #5
