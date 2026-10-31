# Finding classes

For a row of a review findings file: class to rung to owner. The ladder's rungs and its guardrail
criterion stay the authority, and codify's selection rule is strongest first for every input. A
class row names the check its findings usually reach. Walk the ladder from the top: a stronger rung
that can decide the row wins, and the row's owner follows that rung ("Next step per rung" below).
An `invalid-state` row is offered `make-impossible` first; codify only proposes that redesign.

## Class table

| Finding class | Rung | Owner or pointer |
|---|---|---|
| `invalid-state` (a value or combination the code can express but must never hold: two flags that must not both be true, a field that is always set after construction but typed as optional, two ids of different kinds that can be passed in each other's place) | `make-impossible` | `/architecture:improve` when that skill is available, otherwise `/planning:design`; the proposal names the type, data-structure or API change and implements nothing |
| `style` (formatting, whitespace, ordering, naming style) | `editorconfig-severity` | in-repo `.editorconfig` |
| `defined-diagnostic` (a diagnostic an installed analyzer pack or linter already defines: a cited `CAxxxx`/`IDExxxx`/`SAxxxx`, an ESLint, ruff, or markdownlint id, or a rule the pack documents) | `analyzer-pack-rule` | in-repo configuration: enable the rule or raise its severity in `.editorconfig`, `.globalconfig`, or the linter's own config |
| `dotnet-invariant` (a project-specific API or usage invariant in C# expressible over syntax or the semantic model: a banned API, a required attribute, a misuse pattern) | `custom-analyzer` | Microsoft Learn, "Tutorial: Write your first analyzer and code fix" (<https://learn.microsoft.com/en-us/dotnet/csharp/roslyn-sdk/tutorials/how-to-write-csharp-analyzer-code-fix>) |
| `syntactic-pattern` (a code pattern expressible as a syntactic match in any language: a dangerous call, an injection sink, a secret shape, a cross-language invariant; also `dotnet-invariant` in a non-.NET ecosystem) | `semgrep-rule` | the `semgrep-rule-creator` plugin when installed; otherwise Semgrep's rule-writing documentation (<https://docs.semgrep.dev/writing-rules/overview>) |
| `structure` (dependency direction, layering, namespace-to-layer naming, forbidden references) | `architecture-test` | ArchUnitNET (<https://archunitnet.readthedocs.io/>) for .NET; dependency-cruiser (<https://github.com/sverweij/dependency-cruiser>) for JS/TS |
| `process` (commit shape, file placement, generated-file freshness, session behavior: anything observed at tool-call or commit time rather than in source) | `action-guard` | the `harness-config` plugin's automation-gaps audit when enabled; otherwise record the candidate and stop |
| `design-judgment` (readability, correctness reasoning, prose quality) and `unclassified` | `automated-review` | none; the finding stays a review-time judgment |

The `custom-analyzer` rung is .NET-only. The same invariant in any other ecosystem is
`syntactic-pattern`, and falls to the `semgrep-rule` rung.

## Lookup sections

Three sections, keyed the way [the class ladder](../actions/findings.md#2-derive-the-class) reads
them: exact rule id first, then the rule family the id belongs to, then the dimension heading the
row sat under. A row found here names an existing detector or a settled answer, so it fixes the
rung: no stronger rung is walked.

### Rule-id rows (exact match)

The one id form the detector-findings contract allows is `<plugin>/<skill>/rule-<slug>`, so a
match here is byte-exact on the whole id.

Every owner cell below reading "already deterministic: keep the `<plugin>:<skill>` detector" is
gated on that plugin still being enabled in the consuming repo; where it is not, the finding has
no deterministic rung there and falls back to `automated-review`, a review-time judgment, until the
detector is enabled again. The same gate and the same fallback bind the rule-family rows.

| Rule id | Class | Rung | Owner or pointer | Basis |
|---|---|---|---|---|
| `mutation-testing/audit/rule-survivor-productive` | `design-judgment` | `automated-review` | none | the remedy is a covering test whose assertion is a judgment about the code's contract, which no check can state for you |
| `mutation-testing/audit/rule-survivor-unclassified` | `design-judgment` | `automated-review` | none | the row exists because the classification itself was unresolved, so no deterministic rung can be argued for it |
| `mutation-testing/audit/rule-survivor-arid` | `design-judgment` | `automated-review` | none | aridity is a judgment about whether the node is worth testing at all |
| `mutation-testing/audit/rule-survivor-equivalent` | `design-judgment` | `automated-review` | none | equivalence is undecidable in general, so a check that claimed it would be asserting something it cannot know |
| `testing/audit/rule-zero-assertion` | `defined-diagnostic` | `analyzer-pack-rule` | the test-framework analyzer pack already in the project | an assertion-free test body is a whole-method syntactic shape, which is what a test-framework analyzer pack is for; the work is enabling or raising a diagnostic, not writing one |
| `testing/audit/rule-recomputed-expectation` | `dotnet-invariant` | `custom-analyzer` | Microsoft Learn analyzer tutorial (see the class table) | deciding an expected value was recomputed from the code under test needs the semantic model to resolve both sides to the same symbol, which no pack diagnostic states |
| `testing/audit/rule-mock-only-oracle` | `dotnet-invariant` | `custom-analyzer` | Microsoft Learn analyzer tutorial (see the class table) | whether the oracle reaches only mocks is a property of which symbols the assertions touch, again a semantic-model question, and over the project's own mocking library |
| `testing/audit/rule-inert-assertion` | `defined-diagnostic` | `analyzer-pack-rule` | the test-framework analyzer pack already in the project | we map this rule to the pack diagnostic for the test's language, so the work is enabling or raising it, not writing one: xUnit2021, eslint-plugin-jest `valid-expect`, ShellCheck SC2314, Ruff F631. **Pointer**: when choosing the diagnostic to enable, fetch its rule page live: [xUnit2021](https://xunit.net/xunit.analyzers/rules/xUnit2021), [`valid-expect`](https://github.com/jest-community/eslint-plugin-jest/blob/main/docs/rules/valid-expect.md), [SC2314](https://www.shellcheck.net/wiki/SC2314), [F631](https://docs.astral.sh/ruff/rules/assert-tuple/). **As of**: 2026-10-31. **Recheck trigger**: one of those rule pages is renamed, removed or deprecated, or `testing:audit` changes what `rule-inert-assertion` matches |
| `testing/audit/rule-constant-restatement` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `testing:audit` detector | the producing detector is itself the deterministic check, a pattern over the equality's two sides, so the cheapest rung is the one already running |
| `testing/audit/rule-source-text-read` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `testing:audit` detector | as above |
| `testing/audit/rule-conditional-assertion` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `testing:audit` detector | as above |
| `testing/audit/rule-recomputed-derived` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `testing:audit` detector | as above |
| `testing/audit/rule-snapshot-only` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `testing:audit` detector | as above |
| `testing/audit/rule-weak-oracle` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `testing:audit` detector | as above |
| `testing/audit/rule-flaky-passes-suite` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `testing:audit` detector | no analyzer pack reads Playwright `retries` against `failOnFlakyTests` (judgment), so the detector's config read stays the check |
| `testing/audit/rule-only-not-forbidden` | `defined-diagnostic` | `analyzer-pack-rule` | the project's ESLint config | we map this rule to eslint-plugin-playwright `no-focused-test`, enabled in the project's ESLint config. **Pointer**: when enabling it, fetch [its rule page](https://github.com/playwright-community/eslint-plugin-playwright/blob/main/docs/rules/no-focused-test.md) live. **As of**: 2026-10-31. **Recheck trigger**: that rule page is renamed, removed or deprecated, or `testing:audit` changes what `rule-only-not-forbidden` matches |
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
| `harness-config/audit-instructions/rule-coercive-emphasis` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `harness-config:audit-instructions` detector | the producing scanner fires this rule from a pattern over instruction text |
| `harness-config/audit-instructions/rule-blanket-tool-default` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `harness-config:audit-instructions` detector | as above |
| `harness-config/audit-instructions/rule-description-restatement` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `harness-config:audit-instructions` detector | as above |
| `harness-config/audit-instructions/rule-sibling-restatement` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `harness-config:audit-instructions` detector | as above |
| `docs-hygiene/audit-noise/rule-negation-without-positive` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `docs-hygiene:audit-noise` detector | the shape is matched by the producing scanner, so the rung is a configuration decision about that scanner |
| `attribution/audit/rule-verbatim-copy` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `attribution:audit` detector | admission is gated on a fingerprint comparison the producer computes, not on a reader's judgment |
| `attribution/audit/rule-stamp-expired` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `attribution:audit` detector | expiry is a date comparison the producing script performs |
| `attribution/audit/rule-trigger-less-stamp` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `attribution:audit` detector | a missing recheck trigger is a structural absence the producing script observes |
| `attribution/audit/rule-restated-upstream-fact` | `design-judgment` | `automated-review` | none | whether a passage states a fact an external source owns is a panel's judgment, so the family default of "already deterministic" would claim a check the producer does not compute |

### Rule-family rows (prefix match on `<plugin>/<skill>/`)

A lower and distinct ladder step, so an id a producer adds later still lands on its family's
class instead of falling through to prose.

| Family prefix | Class | Rung | Owner or pointer | Basis |
|---|---|---|---|---|
| `mutation-testing/audit/` | `design-judgment` | `automated-review` | none | every rule in this family reports a surviving mutant, whose remedy is a test whose assertion is judgment |
| `testing/audit/` | `dotnet-invariant` | `custom-analyzer` | Microsoft Learn analyzer tutorial (see the class table) | the family's rules are properties of a test's oracle; the family default takes the semantic-model rung, and an individual rule a pack already covers is listed above |
| `ai-slop/audit/` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `ai-slop:audit` detector | the producing detector is the deterministic check for the whole family |
| `harness-config/audit-instructions/` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `harness-config:audit-instructions` detector | as above |
| `docs-hygiene/audit-noise/` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `docs-hygiene:audit-noise` detector | as above |
| `attribution/audit/` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `attribution:audit` detector | as above |

### Dimension rows (the `## By dimension` heading a row sat under)

The dimension enum is open, so this section is a shortcut for the three headings whose mapping
is unambiguous, plus a default that hands everything else to the next ladder step.

| Dimension | Class | Rung | Basis |
|---|---|---|---|
| `architecture` | `structure` | `architecture-test` | the dimension names dependency and layering shape, which is exactly what an architecture test asserts |
| `security` | `syntactic-pattern` | `semgrep-rule` | the recurring security findings a check can catch are sink and secret shapes, which a syntactic matcher expresses in any language |
| `docs` | `design-judgment` | `automated-review` | prose quality is judgment; a docs finding that is mechanical carries a rule id and was already resolved a step earlier |
| any other or unlisted dimension | (none) | (none) | fall through to the judgment step; the enum is open, so an unlisted heading carries no mapping and guessing one would be worse than reading the row |

## Verification record

- **Claim.** The rule-id and rule-family sections restate rule ids another document owns: the
  qualified ids the six producers emit today, and the one id form allowed.
- **Basis.** The detector-findings contract, read at
  <https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/contracts/detector-findings/README.md>,
  cross-checked against each producer's own emitter script for the ids it constructs at run time.
  The `attribution:audit` producer holds crosswalk rows in that contract without an adopters-table
  row, which is why its ids appear here and its adoption status does not.
- **As of.** 2026-09-29.
- **Recheck trigger.** A new producer row lands in that contract's crosswalk, or an existing
  producer's emitter starts constructing an id this table does not list. Either shows up as a
  finding whose id reaches the rule-family step instead of the rule-id step.

Every row above carries its basis in one clause, so a reader can dispute the mapping rather than
inherit it.

## Next step per rung

What the proposal's install step says, for every input. With the ratchet offer on, a counting rung
(`editorconfig-severity`, `analyzer-pack-rule`, `custom-analyzer`, `semgrep-rule`,
`architecture-test`) ends with it: once the rule exists, a count above zero goes to
`/toolchain:ratchet`, and a zero count lands the rule.

- **`make-impossible`**: name the type, data structure or API whose shape lets the invalid state
  exist, and the change that would remove it. Hand it to `/architecture:improve` when that skill is
  available, otherwise to `/planning:design`.
- **`shared-helper`**: name the helper and the lint or check that fails a caller who bypasses it.
- **`editorconfig-severity`**: name the setting and the file; no plugin is involved.
- **`analyzer-pack-rule`**: name the diagnostic id and the config file that raises its severity.
  Where the producing detector already is the deterministic check, the next step is to keep it.
- **`custom-analyzer`**: point at Microsoft Learn, "Tutorial: Write your first analyzer and code
  fix" (<https://learn.microsoft.com/en-us/dotnet/csharp/roslyn-sdk/tutorials/how-to-write-csharp-analyzer-code-fix>).
  This rung is .NET-only; the same invariant elsewhere belongs on the Semgrep rung.
- **`semgrep-rule`**: `/semgrep-rule-creator:semgrep-rule-creator` when that plugin is installed;
  otherwise Semgrep's rule-writing documentation (<https://docs.semgrep.dev/writing-rules/overview>).
- **`architecture-test`**: ArchUnitNET (<https://archunitnet.readthedocs.io/>) for .NET and the
  dependency-cruiser repository docs (<https://github.com/sverweij/dependency-cruiser>) for JS/TS.
- **`action-guard`**: `/harness-config:audit-automation-gaps hooks` when that plugin is enabled,
  presenting the proposal as a candidate; otherwise the proposal records the candidate with its
  frequency, incident history and the enforcement already covering it.
- **`automated-review`**: a `REVIEW.md` line, for a rule only a reviewer applies or a change to how
  severe a finding is. Say that no check catches it.
- **`instruction`**: a `CLAUDE.md`, `AGENTS.md` or rules-file line, placed by section 3.
