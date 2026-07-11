# Decision framework: extract vs inline vs skill vs rule

Full 6-test extraction gate + 5-test keep-inline gate, plus output-type criteria. SKILL.md cites the headline gate (Rule of Three) and links here for the full matrix.

Applies to any repeated text content — markdown (rules, skills, docs), code (constants, helpers, types), config (CI workflows, settings, MCP entries), or mixed clusters that span all three. The principle is the coding Rule of Three / DRY: extract when 3+ instances exist; otherwise inline.

## EXTRACT into shared SSOT only when ALL six tests pass

| # | Test | Why | Evidence |
|---|------|-----|----------|
| 1 | **Rule of Three** — duplication appears in 3+ places | Premature abstraction creates the wrong-abstraction trap; 1-2 instances are usually coincidence, not pattern. Same principle whether the duplicated unit is a markdown heading, a string constant, a helper function, or a CI step | Don Roberts / Fowler *Refactoring* §1; Sandi Metz "The Wrong Abstraction" |
| 2 | **Namable as a stable canonical unit** — the cluster has an identity that can be given one name and referenced by that name | For markdown: a heading or rule name. For code: a function/constant/type identifier. For config: an anchor/include/`$ref` target. Without a stable name, callers can't cite/import unambiguously and the SSOT becomes a grab-bag. For markdown specifically, the unit should also be categorical (vocabulary, constraints, IF-THEN) rather than nuanced reasoning — MDEval finding: providing an external markdown reference does NOT improve a model's Markdown Awareness vs well-designed inline rules ("feeding a reference to an LLM does not bring any benefit for Markdown Awareness; this unexpected finding challenges prevalent assumptions") | Anthropic best-practices "Avoid offering too many options"; MDEval arxiv 2501.15000; Endor Labs anti-pattern avoidance (64% reduction with categorical extraction) |
| 3 | **Stable** — content does NOT change more than 1×/quarter | Volatile SSOTs invalidate downstream sessions' prompt caches on every edit (an always-loaded file that changes often is a cache-miss generator); high churn also drives heading/identifier rename frequency, which compounds the citation-rot risk captured in test #6 below. Code-side equivalent: high churn means callers chase signature changes constantly | Anthropic prompt caching docs (cache TTL hinges on stability — [platform.claude.com/docs/en/build-with-claude/prompt-caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching)); Sandi Metz wrong-abstraction (volatile = signal that the abstraction shape is not yet stable) |
| 4 | **Self-contained** — content has no implicit dependency on caller context | Leaky abstraction = silent failure. For markdown: the extracted block must not say "the prior step" or "as discussed earlier". For code: the helper must not depend on global state the caller happens to set. For config: the include must not reference variables the includer happens to define | Joel Spolsky "Law of Leaky Abstractions"; elements.cloud agent-instruction antipatterns |
| 5 | **Bounded size** — extracted markdown file < 500 lines; extracted code module sized per language idiom | Anthropic's documented best-practice guideline ("Keep SKILL.md body under 500 lines for optimal performance"); over-long files force partial reads and downstream-session cache pressure. For code: each language has its own conventions (small composable modules over monoliths) | Anthropic best-practices "Keep SKILL.md body under 500 lines for optimal performance"; GitHub Copilot 4000-char hard truncation |
| 6 | **One level deep** — referenced directly from caller, never via another reference | Markdown: A.md → B.md → C.md chains compound failure rates (5-20% per step). Code/config: the equivalent rule is no transitive re-export chains; the call site imports/cites the canonical SSOT directly | Anthropic best-practices "Avoid deeply nested references" |

ALL six must pass. Failing one means: keep inline, OR refactor the candidate before extracting (e.g. split categorical bits from reasoning bits, then extract only the categorical bits).

## KEEP INLINE when ANY of these is true

| # | Test | Why |
|---|------|-----|
| A | Single use site OR < 3 instances of duplication | Premature abstraction; wait for the third instance |
| B | Markdown content is reasoning, decision logic, or tradeoff explanation | Indirection breaks down on nuanced content (MDEval finding); for code/config this test usually doesn't apply because the unit is mechanical |
| C | Content is volatile (changes more than monthly) | Citation rot guaranteed (heading/function/anchor renames); cache-invalidation cascade for downstream sessions |
| D | Instances differ in non-trivial ways and would force conditionals/flags inside the SSOT | Sandi Metz wrong-abstraction trap; params/conditionals proliferating IS the signal that the unit is NOT yet stable |
| E | Cluster is small (< ~10 lines) AND specific to one consumer's behavior | Indirection cost > duplication cost; the cite-by-name / import overhead wins |

Any ONE failure here = keep inline. Don't extract just because you can.

## Pre-extraction Tier 0 checklist (lessons-derived discipline)

After the 6-test gate passes a-priori, run these 6 empirical checks BEFORE writing any SSOT file. Each maps to a `context/lessons.md` lesson + an `actions/verify.md` gate. They're additive to the 6+5 framework above — the framework is "is this extractable in principle?", this checklist is "should we actually extract right now, given how the codebase already cites things?".

Run via `/extract-ssot verify <cluster>` for a one-shot result, or apply manually for fast informal checks.

| # | Check | Lesson | Verify gate | Refuse signal |
|---|-------|--------|-------------|---------------|
| A | **Discriminating-phrase grep, not keyword density** | Lesson 1 | Gate 1 | Keyword count > 3 but full-reproduction count < 3 → REFUSE-rule-of-three-fails |
| B | **Pre-existing canonical citation check** | Lesson 2 | Gate 2 | All N call sites already cite `per <canonical>.md "<heading>"` → REFUSE-already-cites-canonical (no work remains) |
| C | **Primary-source citation gate** | Lesson 6 | Gate 3 | All call sites cite a vendor/RFC/spec URL within ~5 lines → REFUSE-primary-source-citation-gate (internal SSOT can't improve) |
| D | **Source-of-truth bifurcation check** | Lesson 8 | Gate 4 | Cluster originates in a top-tier instruction file AND an aggregator rule file with deeper detail → REFUSE-source-of-truth-bifurcation |
| E | **Off-by-one heuristic — different concerns** | Lessons 3+4 | Gate 5 | Step counts / variant shapes diverge non-trivially across instances → REFUSE-off-by-one-different-concern; intentional Path 1/Path 2 bifurcations are preserved |
| F | **LOW-ROI threshold** | Lesson 5 | Gate 6 | Single-sentence body (≤80 words) AND drift ≤ 1×/year → REFUSE-low-roi (inline beats abstraction maintenance) |

If a check fails → REFUSE the extraction with the matching reason code; do NOT silently proceed. Document the refusal in your working notes so future-self knows the cluster was evaluated and rejected with cause.

If ALL checks pass → proceed to the `architect-plan` phase.

## REFACTOR when extraction is wrong (Metz unwind)

Per Sandi Metz "The Wrong Abstraction" (2016), reverse the extraction in three steps:

1. Re-introduce duplication by inlining the abstracted content back into every caller
2. Within each caller, keep ONLY the subset that caller actually needs (delete bits that aren't used)
3. Re-isolate genuine duplication and re-extract with corrected shape

The `unwind` action implements this. Trigger signal: the SSOT has 5+ callers passing different boolean flags or conditional branches — params + conditionals proliferating IS the wrong-abstraction signal.

## Output type: rule file vs skill

Once the 6-test gate passes, choose the SSOT shape. **First check whether an existing file already owns the concept** (top row) — if so, consolidate into it rather than creating anything. The first four rows are the markdown branch this skill ships a citation contract for; the bottom three rows are escape-hatch cases the skill flags during `identify` but defers to language-idiomatic tooling (compiler / linter / IDE refactor / schema-validate are the rename safety net there, not this skill's `/rename-references` sweep).

| Shape | Target | Trigger signals |
|-------|--------|-----------------|
| **Consolidate into existing SSOT home** (markdown) | The existing rule / skill body / doc that already owns the concept — extend it only where a consumer carries nuance the home lacks; create no new file | An existing canonical already documents the concept AND consumers recap it inline instead of citing. Positive output-type form of what `verify` Gate 2 (`REFUSE-already-cites-canonical` fires only when ALL sites already cite) and anti-pattern Shape C (dedup-by-deletion) describe remedially; `identify` flags it as `edit-existing-rule` / `trim-to-citation`. Migration = add citations + delete the recaps; the `/rename-references` sweep is a no-op unless a heading changes |
| **Rule file** (markdown) | Wherever the consuming repository's own conventions place shared rules — default `.claude/rules/<topic>.md` (always-loaded) OR a path-scoped rule file | Vocabulary, IF-THEN rules, hard constraints, ≤500 lines, consumers cite by H3 heading and don't need procedural orchestration |
| **New skill** (markdown + workflow) | `.claude/skills/<name>/SKILL.md`, authored via the consumer's skill-authoring workflow (e.g. the skill-creator plugin) | Workflow with 3+ discrete actions, has its own anti-patterns/evals, consumers invoke `/<name>` to run the workflow rather than read content |
| **Extend existing skill** | New action on an existing action-router skill | The workflow maps cleanly onto an existing skill's concern — same domain, same triggers, same output surface — rather than warranting a new top-level skill |
| **Code module / constants file** | Idiomatic location per language (constants file, shared module, helper class) | Repeated literal, magic number, regex, helper function in source code; callers import by name |
| **Config include / anchor** | Reusable workflow, composite action, YAML anchor + alias, JSON `$ref`, settings include | Repeated stanza in CI / MCP / settings; the tooling supports the include construct |
| **Mixed-canonical** | One canonical owner (usually code or schema), with cross-references from other file classes | Cluster spans 2+ file classes for the same conceptual unit; the canonical definition lives where the runtime authority lives |

Skill-vs-rule heuristic: if the SSOT body is mostly nouns (named units the caller cites), it's a rule file or constants module. If the SSOT body is mostly verbs (steps the caller invokes), it's a skill.

## Worked examples

Each example is generic — pattern-shaped, not tied to one specific extraction. Substitute the actual cluster names and counts when running the framework on a real cluster.

### Example 1: markdown vocabulary → rule file (PASSES gate)

**Cluster:** A vocabulary of CLI verbs / API shapes appears inlined across many prompts, skills, and rules. Each call site reproduces some variation of the same command shape with the same flags.

**6-test gate:**

1. ✅ Rule of Three — well above 3 instances
2. ✅ Namable — each verb has a stable name (the CLI subcommand); content is categorical
3. ✅ Stable — verb signatures change roughly yearly
4. ✅ Self-contained — each verb is independently usable
5. ✅ Bounded — verb table fits well under 500 lines
6. ✅ One level deep — callers cite directly

**Output:** new rule file at the repo's conventional shared-rule location (default `.claude/rules/<topic>.md`) with one H3 per verb. Callers migrate to `per <topic>.md "<verb name>".` Local literal values (PR numbers, run IDs, paths) stay at the call site; only the verb shape moves to the SSOT.

### Example 2: code constants → shared module (PASSES gate)

**Cluster:** The same string literal (or magic number, or regex) appears in many source files. Examples: an error message text, a default timeout, a path prefix, a header name.

**6-test gate:**

1. ✅ Rule of Three — 5+ source files
2. ✅ Namable — gets a clear identifier (e.g. `DefaultTimeout`, `AuthHeaderName`)
3. ✅ Stable — value rarely changes; when it does, all callers must change together
4. ✅ Self-contained — value depends only on itself
5. ✅ Bounded — single declaration
6. ✅ One level deep — callers import the constant directly, no re-export chains

**Output:** constants module / static class / enum at the language's idiomatic location. Callers replace literals with the named import. Compiler/linter catches missed call sites — citation rot is structurally prevented in code, unlike markdown.

### Example 3: mixed cluster spanning code, doc, and config (PASSES gate)

**Cluster:** The same identifier (e.g. an environment variable name, default port, feature-flag key) appears as a string literal in source files, an example in documentation, and a default value in CI / settings YAML.

**6-test gate:**

1. ✅ Rule of Three — at least one instance per file class
2. ✅ Namable — the identifier is the name; the canonical definition lives wherever the runtime owner is (usually code)
3. ✅ Stable — env var / port / flag key changes rarely
4. ✅ Self-contained — the identifier means the same thing in every context
5. ✅ Bounded — the canonical definition is one line / one row
6. ✅ One level deep — each call site references the canonical location directly

**Output:** ONE canonical definition (typically in code as a constant or in a settings schema), THEN call sites in other file classes cite/reference it in their native form — code via import, doc via inline mention, config via include / environment substitution. The SSOT artifact may be small (one constant), but the migration touches every file class.

### Example 4: large cluster with workflow shape → skill (PASSES gate, but procedural)

**Cluster:** Multiple prompts or scripts duplicate a multi-step orchestration (e.g. poll-for-event → classify → react → confirm). Variants differ in params and side-step ordering.

**6-test gate:**

1. ✅ Rule of Three — 5+ instances
2. ⚠️ Namable — yes, but the unit is procedural (verbs), not categorical (nouns)
3. ✅ Stable — workflow shape stable across variants
4. ✅ Self-contained — given params at invocation
5. ⚠️ Bounded — body pushes against 500 lines if all variants are captured inline; needs progressive disclosure to `context/`
6. ✅ One level deep

**Output:** new skill at `.claude/skills/<name>/SKILL.md` with an action menu — NOT a rule file. The skill body holds the orchestration shape; longer reference content goes to `context/`. Callers refactor to `/<skill-name>` invocations with per-instance params.

Skill-vs-rule heuristic restated: if the SSOT body is mostly nouns (named units the caller cites), it's a rule file or constants module. If the SSOT body is mostly verbs (steps the caller invokes), it's a skill.

### Example 5: borderline → defer (FAILS gate)

**Cluster:** Two files have similar (not identical) snippets. A third instance might appear later, or might not.

**6-test gate:**

1. ❌ Rule of Three — only 2 instances
2. ✅ Namable
3. ✅ Stable
4. ✅ Self-contained
5. ✅ Bounded
6. ✅ One level deep

**Output:** REFUSE extraction. Cite Rule of Three. Offer to record a tracking note in the working notes so future-self knows to revisit when the third instance lands. Do NOT silently proceed — premature abstraction is a wrong-abstraction trap that's expensive to reverse.

## Cross-references

- SKILL.md "Output type" — the canonical markdown summary of the output-type table
- SKILL.md "Evidence discipline" — Rule of Three evidence MUST be grep output captured this turn, not recall
- `context/lessons.md` — the empirical observations behind the Pre-extraction Tier 0 checklist
- `actions/verify.md` — the refuse-fast gates implementing the checklist
