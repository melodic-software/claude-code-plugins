# Enforcement-rung crosswalk

Class to rung to owner. The rungs are in fixed cheapest-first order: a class lands on the
cheapest rung whose check can actually assert it, never on a rung that merely could be built.

## Class table

| Finding class | Rung | Owner or pointer |
|---|---|---|
| `style` (formatting, whitespace, ordering, naming style) | `editorconfig-severity` | in-repo `.editorconfig` |
| `defined-diagnostic` (a diagnostic an installed analyzer pack or linter already defines: a cited `CAxxxx`/`IDExxxx`/`SAxxxx`, an ESLint, ruff, or markdownlint id, or a rule the pack documents) | `analyzer-pack-rule` | in-repo configuration: enable the rule or raise its severity in `.editorconfig`, `.globalconfig`, or the linter's own config |
| `dotnet-invariant` (a project-specific API or usage invariant in C# expressible over syntax or the semantic model: a banned API, a required attribute, a misuse pattern) | `custom-analyzer` | Microsoft Learn, "Tutorial: Write your first analyzer and code fix" (<https://learn.microsoft.com/en-us/dotnet/csharp/roslyn-sdk/tutorials/how-to-write-csharp-analyzer-code-fix>) |
| `syntactic-pattern` (a code pattern expressible as a syntactic match in any language: a dangerous call, an injection sink, a secret shape, a cross-language invariant; also `dotnet-invariant` in a non-.NET ecosystem) | `semgrep-rule` | the `semgrep-rule-creator` plugin when installed; otherwise Semgrep's rule-writing documentation (<https://docs.semgrep.dev/writing-rules/overview>) |
| `structure` (dependency direction, layering, namespace-to-layer naming, forbidden references) | `architecture-test` | ArchUnitNET (<https://archunitnet.readthedocs.io/>) for .NET; dependency-cruiser (<https://github.com/sverweij/dependency-cruiser>) for JS/TS |
| `process` (commit shape, file placement, generated-file freshness, session behaviour: anything observed at tool-call or commit time rather than in source) | `hook` | the `claude-config` plugin's automation-gaps audit when installed; otherwise record the candidate and stop |
| `design-judgment` (readability, correctness reasoning, prose quality) and `unclassified` | `llm-only` | none; the finding stays a review-time judgment |

The `custom-analyzer` rung is .NET-only. The same invariant in any other ecosystem is
`syntactic-pattern`, and falls to the `semgrep-rule` rung.

## Lookup sections

Three sections, keyed the way the derivation ladder reads them: exact rule id first, then the
rule family the id belongs to, then the dimension heading the row sat under.

### Rule-id rows (exact match)

The one id form the detector-findings contract allows is `<plugin>/<skill>/rule-<slug>`, so a
match here is byte-exact on the whole id.

| Rule id | Class | Rung | Owner or pointer | Basis |
|---|---|---|---|---|
| `mutation-testing/audit/rule-survivor-productive` | `design-judgment` | `llm-only` | none | the remedy is a covering test whose assertion is a judgment about the code's contract, which no check can state for you |
| `mutation-testing/audit/rule-survivor-unclassified` | `design-judgment` | `llm-only` | none | the row exists because the classification itself was unresolved, so no deterministic rung can be argued for it |
| `mutation-testing/audit/rule-survivor-arid` | `design-judgment` | `llm-only` | none | aridity is a judgment about whether the node is worth testing at all |
| `mutation-testing/audit/rule-survivor-equivalent` | `design-judgment` | `llm-only` | none | equivalence is undecidable in general, so a check that claimed it would be asserting something it cannot know |
| `testing/audit/rule-zero-assertion` | `defined-diagnostic` | `analyzer-pack-rule` | the test-framework analyzer pack already in the project | an assertion-free test body is a whole-method syntactic shape, which is what a test-framework analyzer pack is for; the work is enabling or raising a diagnostic, not writing one |
| `testing/audit/rule-recomputed-expectation` | `dotnet-invariant` | `custom-analyzer` | Microsoft Learn analyzer tutorial (see the class table) | deciding an expected value was recomputed from the code under test needs the semantic model to resolve both sides to the same symbol, which no pack diagnostic states |
| `testing/audit/rule-mock-only-oracle` | `dotnet-invariant` | `custom-analyzer` | Microsoft Learn analyzer tutorial (see the class table) | whether the oracle reaches only mocks is a property of which symbols the assertions touch, again a semantic-model question, and over the project's own mocking library |
| `ai-slop/audit/rule-em-dash` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `ai-slop:audit` detector | the producing detector is itself the deterministic check, so the cheapest rung is the one already running; hold its severity rather than rebuild it |
| `ai-slop/audit/rule-emoji-formatting` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `ai-slop:audit` detector | as above: the detector fires this rule from a pattern, not a judgment |
| `ai-slop/audit/rule-curly-artifacts` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `ai-slop:audit` detector | as above |
| `ai-slop/audit/rule-significance-inflation` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `ai-slop:audit` detector | as above |
| `ai-slop/audit/rule-negative-parallelism` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `ai-slop:audit` detector | as above |
| `ai-slop/audit/rule-challenges-conclusion` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `ai-slop:audit` detector | as above |
| `ai-slop/audit/rule-knowledge-cutoff-disclaimer` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `ai-slop:audit` detector | as above |
| `ai-slop/audit/rule-llm-citation-artifacts` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `ai-slop:audit` detector | as above |
| `ai-slop/audit/rule-utm-params` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `ai-slop:audit` detector | as above |
| `ai-slop/audit/rule-chatbot-artifacts` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `ai-slop:audit` detector | as above |
| `ai-slop/audit/rule-filler-phrases` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `ai-slop:audit` detector | as above |
| `ai-slop/audit/rule-stacked-hedging` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `ai-slop:audit` detector | as above |
| `ai-slop/audit/rule-model-era-phrases` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `ai-slop:audit` detector | as above |
| `ai-slop/audit/rule-ai-vocabulary` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `ai-slop:audit` detector | a density threshold is still a computed rule, not a judgment |
| `ai-slop/audit/rule-copulative-avoidance` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `ai-slop:audit` detector | as above |
| `claude-config/audit-instructions/rule-coercive-emphasis` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `claude-config:audit-instructions` detector | the producing scanner fires this rule from a pattern over instruction text |
| `claude-config/audit-instructions/rule-blanket-tool-default` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `claude-config:audit-instructions` detector | as above |
| `claude-config/audit-instructions/rule-description-restatement` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `claude-config:audit-instructions` detector | as above |
| `claude-config/audit-instructions/rule-sibling-restatement` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `claude-config:audit-instructions` detector | as above |
| `docs-hygiene/audit-noise/rule-negation-without-positive` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `docs-hygiene:audit-noise` detector | the shape is matched by the producing scanner, so the rung is a configuration decision about that scanner |
| `provenance/audit/rule-verbatim-copy` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `provenance:audit` detector | admission is gated on a fingerprint comparison the producer computes, not on a reader's judgment |
| `provenance/audit/rule-stamp-expired` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `provenance:audit` detector | expiry is a date comparison the producing script performs |
| `provenance/audit/rule-trigger-less-stamp` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `provenance:audit` detector | a missing recheck trigger is a structural absence the producing script observes |

### Rule-family rows (prefix match on `<plugin>/<skill>/`)

A lower and distinct ladder step, so an id a producer adds later still lands on its family's
class instead of falling through to prose.

| Family prefix | Class | Rung | Owner or pointer | Basis |
|---|---|---|---|---|
| `mutation-testing/audit/` | `design-judgment` | `llm-only` | none | every rule in this family reports a surviving mutant, whose remedy is a test whose assertion is judgment |
| `testing/audit/` | `dotnet-invariant` | `custom-analyzer` | Microsoft Learn analyzer tutorial (see the class table) | the family's rules are properties of a test's oracle; the family default takes the semantic-model rung, and an individual rule a pack already covers is listed above |
| `ai-slop/audit/` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `ai-slop:audit` detector | the producing detector is the deterministic check for the whole family |
| `claude-config/audit-instructions/` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `claude-config:audit-instructions` detector | as above |
| `docs-hygiene/audit-noise/` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `docs-hygiene:audit-noise` detector | as above |
| `provenance/audit/` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `provenance:audit` detector | as above |

### Dimension rows (the `## By dimension` heading a row sat under)

The dimension enum is open, so this section is a shortcut for the three headings whose mapping
is unambiguous, plus a default that hands everything else to the next ladder step.

| Dimension | Class | Rung | Basis |
|---|---|---|---|
| `architecture` | `structure` | `architecture-test` | the dimension names dependency and layering shape, which is exactly what an architecture test asserts |
| `security` | `syntactic-pattern` | `semgrep-rule` | the recurring security findings a check can catch are sink and secret shapes, which a syntactic matcher expresses in any language |
| `docs` | `design-judgment` | `llm-only` | prose quality is judgment; a docs finding that is mechanical carries a rule id and was already resolved a step earlier |
| any other or unlisted dimension | (none) | (none) | fall through to the judgment step; the enum is open, so an unlisted heading carries no mapping and guessing one would be worse than reading the row |

## Verification record

- **Claim.** The rule-id and rule-family sections restate rule ids another document owns: the
  qualified ids the six producers emit today, and the one id form allowed.
- **Basis.** The detector-findings contract, read at
  <https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/detector-findings/README.md>,
  cross-checked against each producer's own emitter script for the ids it constructs at run time.
  The `provenance:audit` producer holds crosswalk rows in that contract without an adopters-table
  row, which is why its ids appear here and its adoption status does not.
- **As of.** 2026-09-06.
- **Recheck trigger.** A new producer row lands in that contract's crosswalk, or an existing
  producer's emitter starts constructing an id this table does not list. Either shows up as a
  finding whose id reaches the rule-family step instead of the rule-id step.

Every row above carries its basis in one clause, so a reader can dispute the mapping rather than
inherit it.
