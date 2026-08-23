# Decision framework: extract vs inline vs skill vs rule

## Contents

- [Reporting gate vs abstraction gate](#reporting-gate-vs-abstraction-gate)
- [EXTRACT into shared SSOT only when ALL six tests pass](#extract-into-shared-ssot-only-when-all-six-tests-pass)
- [KEEP INLINE when ANY of these is true](#keep-inline-when-any-of-these-is-true)
- [Pre-extraction Tier 0 checklist (lessons-derived discipline)](#pre-extraction-tier-0-checklist-lessons-derived-discipline)
- [REFACTOR when extraction is wrong (Metz unwind)](#refactor-when-extraction-is-wrong-metz-unwind)
- [Output type: rule file vs skill](#output-type-rule-file-vs-skill)
- [Worked examples](#worked-examples)
- [Cross-references](#cross-references)

Full 6-test extraction gate + 5-test keep-inline gate, plus output-type criteria. SKILL.md cites the headline gate (Rule of Three) and links here for the full matrix.

Applies to any repeated text content — markdown (rules, skills, docs), code (constants, helpers, types), config (CI workflows, settings, MCP entries), or mixed clusters that span all three. The principle is the coding Rule of Three / DRY: mint a new shared artifact when 3+ instances exist; below that, fix the duplication in place.

## Reporting gate vs abstraction gate

Two different questions were long collapsed into one threshold. They are separate:

- **Reporting gate** — *should the user be told this duplication exists?* Always yes. Withholding a
  finding does not prevent an abstraction; it prevents a fix.
- **Abstraction gate** — *may a NEW SSOT artifact be minted for it?* Rule of Three, unchanged, plus
  the full 6-test gate below.

Rule of Three gates the second question only. The evidence it rests on — ~19% failure on curated
skills, ~50% on practitioner-authored ones — is evidence about the cost of *creating* a shared
artifact too early. It is not evidence that a maintainer should be kept from seeing a drifting pair
of files.

| Bucket | Rostered? | Permitted remedies | Creates a new artifact? |
|---|---|---|---|
| **N=1** — one consumer inlines a recap of an SSOT that already exists | always | `trim-to-citation`, `normalize-wording` | never |
| **N=2** — two consumers recap a canonical home that already exists (trim both to citations), or two files assert the same contract and neither is the declared owner (name one) | always | `trim-to-citation`, `edit-existing-rule`, `name-an-owner`, `normalize-wording` | never |
| **N≥3** — Rule of Three met | always | all of the above, plus `rule-file` / `new-skill` / `new-action` | only when ALL six tests below pass |

**Lowering the reporting threshold does not lower the abstraction threshold.** The sub-three buckets
offer only non-abstracting remedies — every one of them edits files that already exist and adds no
new indirection hop, so none of them can produce the premature abstraction the Rule of Three exists
to prevent. The guardrail is intact; only the silence is gone.

Two constraints keep the rule-of-one default honest:

1. **N=1 requires an existing canonical home.** A lone paragraph nothing else duplicates is not a
   duplication finding and is not rostered. The bucket is specifically "inline recap of an existing
   SSOT" — the defect is the consumer restating what it should be citing.
2. **Sub-three candidates can never be routed to `rule-file` / `new-skill` / `new-action`.**
   `verify` Gate 1 refuses that pairing with `REFUSE-rule-of-three-fails`.

## EXTRACT into shared SSOT only when ALL six tests pass

| # | Test | Why | Evidence |
|---|------|-----|----------|
| 1 | **Rule of Three** — duplication appears in 3+ places | Premature abstraction creates the wrong-abstraction trap; 1-2 instances are usually coincidence, not pattern — and when they are not, the N=1 / N=2 buckets remedy them in place instead of minting an artifact. Same principle whether the duplicated unit is a markdown heading, a string constant, a helper function, or a CI step | Don Roberts / Fowler *Refactoring* §1; Sandi Metz "The Wrong Abstraction" |
| 2 | **Namable as a stable canonical unit** — the cluster has an identity that can be given one name and referenced by that name | For markdown: a heading or rule name. For code: a function/constant/type identifier. For config: an anchor/include/`$ref` target. Without a stable name, callers can't cite/import unambiguously and the SSOT becomes a grab-bag. For markdown specifically, the unit should also be categorical (vocabulary, constraints, IF-THEN) rather than nuanced reasoning — MDEval finding: providing an external markdown reference does NOT improve a model's Markdown Awareness vs well-designed inline rules ("feeding a reference to an LLM does not bring any benefit for Markdown Awareness; this unexpected finding challenges prevalent assumptions") | Anthropic best-practices "Avoid offering too many options"; MDEval arxiv 2501.15000; Endor Labs anti-pattern avoidance (64% reduction with categorical extraction) |
| 3 | **Stable** — content does NOT change more than 1×/quarter | High churn drives heading/identifier rename frequency, which compounds the citation-rot risk captured in test #6 below; and every edit to an always-loaded file reaches sessions already running only at the next `/clear`, `/compact`, or restart, so a volatile SSOT ships corrections its live consumers do not see (anti-pattern #9). Not a caching cost — a mid-session edit to an always-loaded file keeps the cached prefix. Code-side equivalent: high churn means callers chase signature changes constantly | Claude Code prompt caching, [editing CLAUDE.md mid-session](https://code.claude.com/docs/en/prompt-caching#editing-claude-md-mid-session) (verified 2026-08-04); Sandi Metz wrong-abstraction (volatile = signal that the abstraction shape is not yet stable) |
| 4 | **Self-contained** — content has no implicit dependency on caller context | Leaky abstraction = silent failure. For markdown: the extracted block must not say "the prior step" or "as discussed earlier". For code: the helper must not depend on global state the caller happens to set. For config: the include must not reference variables the includer happens to define | Joel Spolsky "Law of Leaky Abstractions"; elements.cloud agent-instruction antipatterns |
| 5 | **Bounded size** — extracted markdown file < 500 lines; extracted code module sized per language idiom | Anthropic's documented best-practice guideline ("Keep SKILL.md body under 500 lines for optimal performance"); over-long files force partial reads and downstream-session cache pressure. For code: each language has its own conventions (small composable modules over monoliths) | Anthropic best-practices "Keep SKILL.md body under 500 lines for optimal performance"; GitHub Copilot 4000-char hard truncation |
| 6 | **One level deep** — referenced directly from caller, never via another reference | Markdown: A.md → B.md → C.md chains compound failure rates (5-20% per step). Code/config: the equivalent rule is no transitive re-export chains; the call site imports/cites the canonical SSOT directly | Anthropic best-practices "Avoid deeply nested references" |

ALL six must pass — and they gate ONE thing: creating a new SSOT artifact (`rule-file` /
`new-skill` / `new-action`). They do not gate reporting, and they do not gate the non-abstracting
remedies (`trim-to-citation`, `normalize-wording`, `name-an-owner`, `edit-existing-rule`), which
edit existing files and introduce no new indirection.

Failing one means: keep the content where it is, OR refactor the candidate before extracting (e.g. split categorical bits from reasoning bits, then extract only the categorical bits). Either way the candidate stays on the roster in its bucket with the remedies that bucket allows.

## KEEP INLINE when ANY of these is true

"Keep inline" here means "do not lift this into a new artifact" — not "say nothing". A candidate
kept inline is still rostered in its bucket and still gets that bucket's non-abstracting remedies.

| # | Test | Why |
|---|------|-----|
| A | Single use site OR < 3 instances of duplication | No new artifact — premature abstraction; wait for the third instance. The content stays where it is, and the candidate is rostered as N=1 or N=2 with `trim-to-citation` / `normalize-wording` / `name-an-owner` / `edit-existing-rule` on the table |
| B | Markdown content is reasoning, decision logic, or tradeoff explanation | Indirection breaks down on nuanced content (MDEval finding); for code/config this test usually doesn't apply because the unit is mechanical |
| C | Content is volatile (changes more than monthly) | Citation rot guaranteed (heading/function/anchor renames); and corrections ship that live consumers do not see until their next `/clear`, `/compact`, or restart (anti-pattern #9) |
| D | Instances differ in non-trivial ways and would force conditionals/flags inside the SSOT | Sandi Metz wrong-abstraction trap; params/conditionals proliferating IS the signal that the unit is NOT yet stable |
| E | Cluster is small (< ~10 lines) AND specific to one consumer's behavior | Indirection cost > duplication cost; the cite-by-name / import overhead wins |

Any ONE failure here = no new artifact. Don't extract just because you can — and don't go quiet just because you didn't.

## Pre-extraction Tier 0 checklist (lessons-derived discipline)

After the 6-test gate passes a-priori, run these 6 empirical checks BEFORE writing any SSOT file. Each maps to a `context/lessons.md` lesson + an `actions/verify.md` gate. They're additive to the 6+5 framework above — the framework is "is this extractable in principle?", this checklist is "should we actually extract right now, given how the codebase already cites things?".

Run via `/docs-hygiene:extract-ssot verify <cluster>` for a one-shot result, or apply manually for fast informal checks.

| # | Check | Lesson | Verify gate | Refuse signal |
|---|-------|--------|-------------|---------------|
| A | **Discriminating-phrase grep, not keyword density** | Lesson 1 | Gate 1 | Keyword count > 3 but full-reproduction count < 3 → bucket is N=1 or N=2; an artifact-creating output there → REFUSE-rule-of-three-fails (the non-abstracting remedies still stand) |
| B | **Pre-existing canonical citation check** | Lesson 2 | Gate 2 | All N call sites already cite `per <canonical>.md "<heading>"` → REFUSE-already-cites-canonical (no work remains) |
| C | **Primary-source citation gate** | Lesson 6 | Gate 3 | All call sites cite a vendor/RFC/spec URL within ~5 lines → REFUSE-primary-source-citation-gate (internal SSOT can't improve) |
| D | **Source-of-truth bifurcation check** | Lesson 8 | Gate 4 | Cluster originates in a top-tier instruction file AND an aggregator rule file with deeper detail, serving two named audiences → intentional, REFUSE-source-of-truth-bifurcation. Same contract, same audience, no declared owner → accidental, the N=2 bucket's own defect: `name-an-owner` |
| E | **Off-by-one heuristic — different concerns** | Lessons 3+4 | Gate 5 | Step counts / variant shapes diverge non-trivially across instances → REFUSE-off-by-one-different-concern; intentional Path 1/Path 2 bifurcations are preserved |
| F | **LOW-ROI threshold** | Lesson 5 | Gate 6 | Single-sentence body (≤80 words) AND drift ≤ 1×/year → REFUSE-low-roi (inline beats abstraction maintenance) |

If a check fails → REFUSE the extraction with the matching reason code; do NOT silently proceed. Document the refusal in your working notes so future-self knows the cluster was evaluated and rejected with cause. Check A is the exception in shape rather than in force: it refuses the artifact, not the finding — the candidate keeps its bucket and its non-abstracting remedies.

If ALL checks pass → proceed to the `architect-plan` phase.

## REFACTOR when extraction is wrong (Metz unwind)

Per Sandi Metz "The Wrong Abstraction" (2016), reverse the extraction in three steps:

1. Re-introduce duplication by inlining the abstracted content back into every caller
2. Within each caller, keep ONLY the subset that caller actually needs (delete bits that aren't used)
3. Re-isolate genuine duplication and re-extract with corrected shape

The `unwind` action implements this. Trigger signal: the SSOT has 5+ callers passing different boolean flags or conditional branches — params + conditionals proliferating IS the wrong-abstraction signal.

## Output type: rule file vs skill

Choose the SSOT shape from the candidate's bucket first, then its content shape. **Check whether an existing file already owns the concept** (top rows) — if so, consolidate into it rather than creating anything. The first six rows are the markdown branch this skill ships a citation contract for; the bottom three rows are escape-hatch cases the skill flags during `identify` but defers to language-idiomatic tooling (compiler / linter / IDE refactor / schema-validate are the rename safety net there, not this skill's `/docs-hygiene:rename-references` sweep).

The **Artifact?** column is the abstraction gate made visible: only the rows marked YES are reachable at N≥3, and only after all six tests pass.

| Shape | Artifact? | Target | Trigger signals |
|-------|-----------|--------|-----------------|
| **Consolidate into existing SSOT home** (markdown) | no new artifact | The existing rule / skill body / doc that already owns the concept — extend it only where a consumer carries nuance the home lacks; create no new file | An existing canonical already documents the concept AND consumers recap it inline instead of citing. Positive output-type form of what `verify` Gate 2 (`REFUSE-already-cites-canonical` fires only when ALL sites already cite) and anti-pattern Shape C (dedup-by-deletion) describe remedially; `identify` flags it as `edit-existing-rule` / `trim-to-citation`. Migration = add citations + delete the recaps; the `/docs-hygiene:rename-references` sweep is a no-op unless a heading changes. Available in every bucket |
| **`normalize-wording`** (markdown) | no new artifact | Every instance, edited in place onto the canonical or agreed wording | The instances say the same thing in drifted phrasings and the drift itself is the defect — a reader cannot tell whether the difference is meaningful. Available in every bucket, including N=1 |
| **`name-an-owner`** (markdown) | no new artifact | One of the two existing files, declared canonical; the other rewritten to cite it | Accidental source-of-truth bifurcation: two files assert the same contract for the same audience and neither is declared the owner (anti-pattern #11, accidental branch). The N=2 bucket's default remedy. Minting a third file to own the contract is NOT this remedy |
| **Rule file** (markdown) | **YES — N≥3 only** | Wherever the consuming repository's own conventions place shared rules — default `.claude/rules/<topic>.md` (always-loaded) OR a path-scoped rule file | Vocabulary, IF-THEN rules, hard constraints, ≤500 lines, consumers cite by H3 heading and don't need procedural orchestration |
| **New skill** (markdown + workflow) | **YES — N≥3 only** | `.claude/skills/<name>/SKILL.md`, authored via the consumer's skill-authoring workflow (e.g. the skill-creator plugin) | Workflow with 3+ discrete actions, has its own anti-patterns/evals, consumers invoke `/<name>` to run the workflow rather than read content |
| **Extend existing skill** | **YES — N≥3 only** | New action on an existing action-router skill | The workflow maps cleanly onto an existing skill's concern — same domain, same triggers, same output surface — rather than warranting a new top-level skill |
| **Code module / constants file** | advisory — out of scope | Idiomatic location per language (constants file, shared module, helper class) | Repeated literal, magic number, regex, helper function in source code; callers import by name |
| **Config include / anchor** | advisory — out of scope | Reusable workflow, composite action, YAML anchor + alias, JSON `$ref`, settings include | Repeated stanza in CI / MCP / settings; the tooling supports the include construct |
| **Mixed-canonical** | advisory — out of scope | One canonical owner (usually code or schema), with cross-references from other file classes | Cluster spans 2+ file classes for the same conceptual unit; the canonical definition lives where the runtime authority lives |

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

### Example 5: two instances → N=2 bucket, no new artifact (FAILS the abstraction gate, PASSES reporting)

**Cluster:** Two files assert the same contract in similar (not identical) wording. Neither is declared the owner. A third instance might appear later, or might not.

**6-test gate (gates artifact creation only):**

1. ❌ Rule of Three — only 2 instances
2. ✅ Namable
3. ✅ Stable
4. ✅ Self-contained
5. ✅ Bounded
6. ✅ One level deep

**Output:** the candidate is **rostered in the N=2 bucket** with its instance count — it is not discarded. Creating a `rule-file` / `new-skill` / `new-action` for it is REFUSED (`REFUSE-rule-of-three-fails`); cite Rule of Three. What IS offered:

- `name-an-owner` — declare the better-placed of the two files canonical, rewrite the other to cite it. This resolves the drift without adding a third file.
- `edit-existing-rule` — if one of the two is already the natural home, extend it where the other carries nuance it lacks.
- `normalize-wording` — if the two have already drifted, align them before (or instead of) naming an owner.

Also record a tracking note in the working notes so future-self knows to revisit if a third instance lands. Do NOT silently proceed to an artifact — premature abstraction is a wrong-abstraction trap that's expensive to reverse — and do NOT silently drop the finding: two undeclared canonicals asserting one contract is exactly the bifurcation that drifts (anti-pattern #11, accidental branch).

### Example 6: one instance → N=1 bucket, trim to a citation (no gate to run)

**Cluster:** A canonical rule file already owns a constraint. One skill body restates it in a paragraph of its own instead of citing it, and the restatement has drifted a word or two from the home's wording.

**Abstraction gate:** not run. Nothing would be created — the SSOT already exists.

**Output:** rostered in the **N=1 bucket** (the SSOT-existence check is what admits it; a lone paragraph with no canonical home would not be). Remedies: `trim-to-citation` — replace the recap with `per <rule>.md "<exact heading>"` plus a ≤80-char inline summary — and `normalize-wording` if the drifted phrasing must survive anywhere. If the site ALREADY cites the home correctly, there is no work: `verify` Gate 2 returns `REFUSE-already-cites-canonical`.

## Cross-references

- SKILL.md "Output type" — the canonical markdown summary of the output-type table
- SKILL.md "Decision framework" — the headline reporting-gate / abstraction-gate split and the bucket table
- SKILL.md "Evidence discipline" — Rule of Three evidence MUST be grep output captured this turn, not recall
- `context/lessons.md` — the empirical observations behind the Pre-extraction Tier 0 checklist
- `actions/verify.md` — the refuse-fast gates implementing the checklist
