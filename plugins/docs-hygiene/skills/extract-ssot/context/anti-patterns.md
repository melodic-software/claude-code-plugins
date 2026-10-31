# Anti-patterns guarded

## Contents

- [1. Citation rot](#1-citation-rot)
- [2. Over-indirection](#2-over-indirection)
- [3. Leaky abstraction](#3-leaky-abstraction)
- [4. Loss of locality](#4-loss-of-locality)
- [5. Reference resolution failure](#5-reference-resolution-failure)
- [6. Wrong abstraction (Sandi Metz failure mode)](#6-wrong-abstraction-sandi-metz-failure-mode)
- [7. Premature extraction](#7-premature-extraction)
- [8. Self-generated SSOT](#8-self-generated-ssot)
- [9. Always-loaded SSOT propagation lag](#9-always-loaded-ssot-propagation-lag)
- [10. Encapsulation violation](#10-encapsulation-violation)
- [11. Source-of-truth bifurcation (REFUSE trigger)](#11-source-of-truth-bifurcation-refuse-trigger)
- [12. Primary-source citation gate (REFUSE trigger)](#12-primary-source-citation-gate-refuse-trigger)
- [13. Shape C: dedup-by-deletion (POSITIVE pattern)](#13-shape-c-dedup-by-deletion-positive-pattern)
- [Cross-references](#cross-references)

13-pattern taxonomy, each with pattern, symptom, and mitigation. Framed for markdown extraction but applicable to code and config; file-class adaptations are noted per pattern.

## 1. Citation rot

**Pattern.** A heading rename in the extracted file silently breaks every reference. Callers keep the OLD heading text; the agent reads the stale citation and either follows a dead link or hallucinates content matching the old heading name.

**Symptom.** Caller text reads `per X.md "Old Heading"`; X.md no longer has an H3 with that exact text. A `/docs-hygiene:rename-references` sweep would have caught it.

**Code/config analog.** A function/constant/anchor rename breaks every `import`, `using`, or `$ref` pinning the old name. Same mitigation: the sweep + IDE rename refactor.

**Mitigation.**

1. Cite by EXACT heading text (markdown), exact identifier (code), exact anchor (config), never by line number or section number
2. After ANY heading/identifier/anchor edit in an SSOT, invoke `/docs-hygiene:rename-references` via the Skill tool immediately. It sweeps all 10 syntactic forms, not just pure-token grep
3. The SSOT file should include a `## Recheck triggers` section, where a rename row triggers the sweep
4. For code: prefer language-aware refactor (IDE / Roslyn / ts-morph) over text grep; combine with `/docs-hygiene:rename-references` for non-source references (docs, configs)

## 2. Over-indirection

**Pattern.** A.md → B.md → C.md chains. The reader follows 2-3 links to assemble meaning; per-link failure rate compounds.

**Symptom.** A skill body cites a rule file that cites another rule file for the same domain. Anthropic's "head -100" partial-read failure mode triggers when the chain is deep.

**Code/config analog.** Re-export chains (`module-A` re-exports `module-B`, which re-exports `module-C`). The same one-level-deep rule applies: the call site imports the canonical SSOT directly.

**Mitigation.**

1. Enforce "one level deep": refuse to ship the extraction if the SSOT itself references another extracted SSOT for the same domain
2. If two SSOT files cover related domains, either merge them OR cite both directly from the caller (one level each)
3. Lint check: grep the extracted SSOT for `\.md "` patterns; warn on >2 references to OTHER `.md` files
4. Code: ban re-export-only modules (`export * from "./other"`); each module owns its own surface

## 3. Leaky abstraction

**Pattern.** The extracted file assumes caller context: "the prior step", "as discussed earlier", "this command above", "that flag we mentioned".

**Symptom.** Read in isolation, the extracted file is nonsense.

**Code/config analog.** A helper depends on global state the caller happens to set (mutable singleton, ambient context, an env var only one caller exports), or a config include references variables only the includer defines. Mitigation: make dependencies explicit (parameters, dependency injection, required-input declaration).

**Mitigation.**

1. Self-test: read the extracted file in isolation and ask "does this make sense without the surrounding context I just came from?"
2. Lint pattern (markdown): detect context-assuming phrases via grep for `prior`, `earlier`, `above`, `previous`, `as mentioned`, `as discussed`, `the X we`, `that step`
3. Code: pure-function preference; explicit parameters over ambient context; document required setup at the import site
4. Config: declared inputs at the include site; no implicit variable inheritance
5. Rewrite to self-contained form OR refuse extraction

## 4. Loss of locality

**Pattern.** The reader must jump 3+ files to understand intent at the call site. Cite-by-name without inline context strips ALL meaning from the caller.

**Symptom.** Caller text reads `per X.md "Y"` and nothing else; the reader has no idea what Y does or why it matters here.

**Code/config analog.** A bare `import { someThing } from "./util"` with no usage context nearby, or YAML `<<: *anchor` with no comment naming what the anchor holds.

**Mitigation.**

1. Cite-by-name AND inline 1-line summary at every call site. Template: `per <file>.md "<heading>": <≤80 char shape description>`
2. The summary lets a reader skimming the caller understand the SHAPE of the cited rule without clicking through
3. Code: name imports for what they do, not where they live; cluster related imports; brief comment at non-obvious call sites
4. Config: name anchors descriptively (`&dotnet-build-defaults` not `&base`); short comment above the alias if intent isn't obvious
5. Full markdown contract in `citation-form.md`

## 5. Reference resolution failure

**Pattern.** Heading renamed in the SSOT; the agent searches for the caller's old citation text, fails to find it, and hallucinates content matching the old heading name.

**Symptom.** Citation rot (#1) seen from the AGENT's side at read time: it confidently acts as if the citation resolved when it didn't.

**Mitigation.**

1. The SSOT file ships with a `## Stable headings: change requires sweep-references` section listing exact anchor text + dependent call sites
2. Verify before acting: when a citation says `per X.md "Y"`, the agent MUST grep X.md for the literal heading "Y" before acting on assumed content
3. If citation-resolution hallucination becomes measurable, add resolution-time verification tooling (a hook or lint that greps the cited heading on read/write)

## 6. Wrong abstraction (Sandi Metz failure mode)

**Pattern.** The extracted SSOT has 5+ callers, each passing different boolean flags or conditional branches. Proliferating params + conditionals IS the failure signal.

**Symptom.** Callers read `/<skill-name> <flag-A> <flag-B> --variant=Q`, each with a unique combination; the SSOT body is a switch-statement of `if flag-A then ... else if flag-B then ...`.

**Mitigation.**

1. The `unwind` action implements Metz's 3-step recovery:
   - Re-introduce duplication by inlining the SSOT body back into every caller
   - Within each caller, keep only the subset that caller actually needs
   - Delete unneeded bits per caller
   - Re-isolate genuine duplication and re-extract with corrected shape
2. Record the unwind decision in the working notes (it is a hard-to-reverse call)
3. After unwind, re-run the `identify` action; only re-extract if Rule of Three still holds with the corrected shape

## 7. Premature extraction

**Pattern.** Extracting at the first or second instance of perceived duplication: two prompts do similar (not identical) things, and the agent extracts a "shared helper" before a third instance proves the pattern.

**Symptom.** The SSOT has 2 callers; one is awkward because the shape was guessed from one strong example + one weak one.

**Mitigation.**

1. The `identify` action requires evidence of 3+ instances before suggesting an artifact-creating output (`rule-file` / `new-skill` / `new-action`), and that evidence is Tier 0 grep output captured this turn, not recall
2. Refuse CREATION when only 1-2 instances exist (`verify` Gate 1, `REFUSE-rule-of-three-fails`); cite Rule of Three with author attribution (Don Roberts / Fowler)
3. Do NOT refuse to report it. The candidate stays on the roster in its N=1 or N=2 bucket with that bucket's non-abstracting remedies: `trim-to-citation`, `normalize-wording`, `name-an-owner`, `edit-existing-rule`. Each edits files that already exist, so none can produce a premature abstraction; suppressing the finding would only prevent the fix
4. Offer to record a tracking note in the working notes to revisit when the third instance lands

## 8. Self-generated SSOT

**Pattern.** The model authors a skill or rule it cannot reliably consume. SkillsBench negative finding: self-generated skills provide NO benefit on average; human curation is the only reliable path. The dated record for that finding is `context/decision-framework.md`, "The SkillsBench record".

**Symptom.** An agent wrote the SSOT end-to-end with no human review at any phase boundary; eval cases (if any) were also model-authored. Failure rate higher than ad-hoc inline.

**Mitigation.**

1. SSOT output goes through human review: the user stages, commits, and reviews the diff
2. Phase boundaries surface the diff to the user explicitly; never auto-stage/commit/push
3. Eval cases for any new skill MUST be human-reviewed against expected output before declaring done

## 9. Always-loaded SSOT propagation lag

**Pattern.** Extraction moves content into an always-loaded file that then gets edited often. The always-loaded files here are `CLAUDE.md` and unscoped `.claude/rules/` files; a rule with `paths:` frontmatter loads lazily, so an edit made before it loads can still reach a session. We treat a running session as keeping the version it loaded: a correction lands in the repo while every live consumer follows the superseded version until it reloads its instructions.

**Scope fence: Claude Code sessions, and the cost is propagation, not caching.** We do not count SSOT edit frequency as a distinct driver of cache misses in Claude Code sessions: a committed edit affects prefix sharing no differently from any other commit. A volatility cost on the API surface is real, but it reaches an Agent SDK fleet assembling one shared prefix across machines, not the tracked-markdown extractions this skill scopes to.

- **Pointer**: for what a mid-session edit does, when the new content loads, and what keys prefix sharing, fetch [editing CLAUDE.md mid-session](https://code.claude.com/docs/en/prompt-caching#editing-claude-md-mid-session) and [cache scope](https://code.claude.com/docs/en/prompt-caching#cache-scope) live; for the API surface, [cache storage and sharing](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#cache-storage-and-sharing).
- **As of**: 2026-10-11
- **Recheck trigger**: the prompt-caching page changes how a mid-session CLAUDE.md edit affects the cached prefix or when it loads; the cache-scope section stops keying sharing on the startup git-status snapshot; or the API cache-storage-and-sharing section changes what a cache entry is shared across or what keys it.

**Symptom.** A rule corrected hours ago is still violated by long-running sessions; two concurrent sessions in the same repo follow different versions of the same rule.

**Mitigation.**

1. Decision-framework test #3 (Stable: content changes <1×/quarter) is the up-front gate
2. If the SSOT must be edited frequently, split it: stable categorical bits stay in the always-loaded SSOT, volatile narrative moves to a surface that loads late enough to see corrections, such as a skill body (injects at invocation), a `paths:`-scoped rule (loads when Claude first works with a matching file; for the exact trigger list, fetch [path-specific rules](https://code.claude.com/docs/en/memory#path-specific-rules) live; as of 2026-10-10, recheck when that section changes its trigger list), or a file consulted on demand. Going back inline helps only when the original home was itself lazy-loaded; inline in `CLAUDE.md` or an unscoped rule is the same always-loaded surface with the same lag
3. A Recheck-triggers section in the SSOT documents anticipated edit frequency; if it drifts >1×/month, raise it as a side observation
4. After a correction live sessions must honor, say so. The fix reaches them only when they reload instructions (which actions do that: the "editing CLAUDE.md mid-session" pointer under the scope fence above)

## 10. Encapsulation violation

**Pattern.** A caller references skill internals (`.claude/skills/<X>/scripts/<file>`, `<X>/context/<topic>.md`, `<X>/actions/<name>.md`, `<X>/reference/<file>.md`) instead of the `/X` invocation, bypassing the skill's public API and tying the caller to internal layout that may move.

**Symptom.** Grep `.claude/skills/[^/]+/(context|actions|reference)` against caller files returns matches; the caller reads file content directly rather than invoking the skill action that uses it.

**Mitigation.**

1. The `execute` action converts external skill-internals refs back to `/X` invocations as part of the work, NOT preserved
2. `scripts/*.sh` is the documented public-API exception. Those CAN be cited externally (see `/docs-hygiene:audit-encapsulation`)
3. If the caller's use case has no public action covering it, surface as a side observation (NOT fix-in-passing). The skill needs an action added before the caller can route through the public API
4. Detection grep + remediation paths: `/docs-hygiene:audit-encapsulation`

## 11. Source-of-truth bifurcation (REFUSE trigger)

**Pattern.** A concept legitimately exists at TWO tiers: a top-level always-loaded source (`CLAUDE.md` / `AGENTS.md`) for the every-session audience, AND a deep-disclosure aggregator rule file for hook/skill/script authors who need detection mechanics or implementation detail. Both are first-class canonicals serving distinct audiences. Forcing the instruction file to cite the rule creates a citation cycle.

**Intentional vs accidental: the distinction that decides the verdict.** The REFUSE trigger
protects the INTENTIONAL case: two tiers, two named audiences, a split someone chose. The
accidental case is the opposite problem: two files assert the same contract for the SAME audience
and NEITHER is the declared owner, so nothing keeps them in sync and they drift. That is a defect,
not a design.

The **N=2 bucket is how accidental bifurcation reaches the user**: it is the most common form of
this defect, rostered rather than discarded. `verify` Gate 4 splits the two: intentional refuses as
below; accidental PROCEEDs at `bucket: N=2` with the remedy **`name-an-owner`**. Declare one of the
two existing files canonical and make the other cite it. No third file is created; minting one
would be the premature abstraction Rule of Three guards against.

**Symptom.** A survey claims "N inline reproductions of <fact>" but Tier 0 grep shows 1 reproduction in the instruction file (top-tier canonical) + 1 in a rule file (aggregator) + N-2 single-concern call sites that need only a slice. Forcing single-citation extraction collapses two legitimate canonicals into one.

**Code/config analog.** The same fact lives in a public README (top-tier audience) AND a developer-guide reference doc; collapsing the README to cite the dev-guide breaks its stand-alone value for the entry-point audience.

**Mitigation.**

1. The `verify` action Gate 4 detects bifurcation and classifies it. Intentional (distinct named audiences) → refuses extraction with `REFUSE-source-of-truth-bifurcation`. Accidental (same audience, no declared owner) → PROCEED at `bucket: N=2` with `name-an-owner` / `edit-existing-rule` / `normalize-wording`
2. Document both canonicals + their respective audiences in the rule file if not already explicit, so the next pass reads the split as intentional
3. Single-concern call sites can still cite either canonical (whichever serves their narrower scope). Keep their narrow-slice usage rather than forcing whole-fact citation
4. **Verbatim source.** `lessons.md` Lesson 8.

## 12. Primary-source citation gate (REFUSE trigger)

**Pattern.** All call sites already cite a primary-source URL directly (vendor doc, RFC, language spec). An internal SSOT cannot improve on a primary URL the consumer already inlines.

**Symptom.** Pre-extraction grep shows every call site contains a primary-source URL within ~5 lines. The verbatim fraction across sites is near 0% because each site frames the primary fact for its own concern.

**Code/config analog.** Code already imports a typed constant from a third-party package; a wrapper file re-exporting it adds indirection without value.

**Mitigation.**

1. The `verify` action Gate 3 detects primary-URL coverage; refuses with `REFUSE-primary-source-citation-gate`
2. Internal SSOT is for repeated *internal-vocabulary* claims (where there IS no primary source), NOT re-statements of facts the primary publisher owns
3. If centralization is desired anyway, extract at MOST a 1-line "prescribed upstream: <URL>" statement, NOT the multi-form derivation
4. **Recheck trigger:** if the primary URL goes 404, all sites need a fallback; that's the moment to revisit
5. **Verbatim source.** `lessons.md` Lesson 6.

## 13. Shape C: dedup-by-deletion (POSITIVE pattern)

**Pattern (positive, and it applies when the cluster IS already SSOT-shaped).** When an existing canonical SSOT already documents the full content and consumers paraphrase it as a TL;DR, the right action is NOT extraction (it already exists) but DELETION of the redundant paraphrases. Keep the directive the consumer acts on (e.g. `Read X.md first`); delete the redundant TL;DR tail prose.

**Symptom.** The cluster body across N consumers reads as a restatement of an existing canonical's intro. Consumers reference the canonical but ALSO restate its content nearby; the redundancy is in the consumers.

**Code/config analog.** Consumers `import` a helper AND inline a copy of its body "for clarity"; delete the copy, the import is sufficient.

**When to apply.**

- An existing rule file or skill body already serves as the SSOT
- 3+ consumers paraphrase that SSOT's content while ALSO referencing the SSOT by name
- The paraphrase adds zero unique signal (it's strictly a restatement)
- Per-consumer intentional deltas (e.g. prompt-specific phase pointers, custom constraints) are NOT in the redundant body and stay inline

**Mitigation / execution.**

1. The `verify` action Gate 2 (pre-existing canonical citation) is the entry point. If it returns `REFUSE-already-cites-canonical` AND the consumer ALSO has a redundant paraphrase nearby, that's the Shape C signal
2. Run a deletion-only sweep: for each consumer, identify the redundant TL;DR tail; delete; preserve the directives the consumer acts on + per-consumer intentional deltas
3. No new file. No `/docs-hygiene:rename-references` sweep (no identifier change). Pure dead-text removal
4. **Verbatim source.** `lessons.md` Lesson 9.

**When NOT to apply.**

- The consumer paraphrase carries unique framing (concern-driven drift per Lesson 7): keep inline
- The "SSOT" is itself just a paraphrase of a primary-source URL (Lesson 6): don't grow the redundancy
- The consumer is intentionally short-form (1-line teaching mention, not full restatement): leave as-is per Lesson 1's exclusion

## Cross-references

- `decision-framework.md`: when to extract (avoiding patterns 6-9 up front); "Pre-extraction Tier 0 checklist" formalizes #11/#12/#13
- `citation-form.md`: anti-patterns 1, 4, 5 mitigation contract for markdown call sites; for code/config see SKILL.md "Output type"
- `/docs-hygiene:audit-encapsulation`: anti-pattern 10 detection + remediation matrix (separate skill)
- `execution-checklist.md`: per-phase sanity checks that catch each anti-pattern
- `lessons.md`: empirical batch-derived patterns; #11 ↔ Lesson 8, #12 ↔ Lesson 6, #13 ↔ Lesson 9
- `actions/verify.md`: refuse-fast gates implementing anti-patterns #11 (Gate 4), #12 (Gate 3), #13 (Gate 2 entry-point); Gates 1/5/6 implement Lessons 1/3+4/5 (informational, not refuse-anti-patterns)
- SKILL.md "Evidence discipline": verify-before-acting for citation resolution (#5); Tier 0 evidence requirement for the #11/#12/#13 detection greps
- `/docs-hygiene:rename-references`: the 10-pattern sweep that catches #1, #4, #5
