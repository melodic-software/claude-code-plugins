# Finding classes

For a row of a review findings file: class to rung to hand-off. The ladder's rungs and its
guardrail criterion stay the authority, and codify's selection rule is strongest first for every
input. A class row names the check its findings usually reach. Walk the ladder from the top: a
stronger rung that can decide the row wins, and the row's hand-off follows that rung ("Next step per
rung" below). An `invalid-state` row is offered `make-impossible` first; codify only proposes that
redesign.

A class names what the check must decide, never a language or a product. Codify picks the rung and
proves the check; the build is handed off. A **build hand-off** is the rung, the check to prove and
the requirement that the check's message names the fix, with `/implementation:implement` named as
the builder. When that skill is available, hand it over; otherwise the proposal stops there, with
the rung, the check and the builder stated. The check is built in the repository's own tooling, the
analyzer, matcher or test library it already runs; codify names no product of its own.

## Class table

| Finding class | Rung | Hand-off |
|---|---|---|
| `invalid-state` (a value or combination the code can express but must never hold: two flags that must not both be true, a field that is always set after construction but typed as optional, two ids of different kinds that can be passed in each other's place) | `make-impossible` | `/architecture:improve` when that skill is available, otherwise `/planning:design`; the proposal names the type, data-structure or API change and implements nothing |
| `style` (formatting, whitespace, ordering, naming style) | `formatter` when the `fix-cmd` of the repository's ecosystem record (`.claude/ecosystems/<ecosystem>.yaml`) can rewrite the code into the rule's shape; otherwise `editorconfig-severity` | build hand-off: the format setting that command reads, or the setting in the in-repo `.editorconfig` |
| `defined-diagnostic` (a diagnostic an installed analyzer pack or linter already defines: a cited diagnostic id, or a rule the pack documents) | `analyzer-pack-rule` | build hand-off: enable the rule or raise its severity in the configuration the repository already uses for that pack |
| `semantic-invariant` (a project-specific API or usage invariant that needs meaning, not syntax, in any language: a banned API resolved by symbol, a required attribute, a misuse pattern that depends on types or on which symbol a call reaches) | `custom-analyzer` | build hand-off: an analyzer for the compiler or linter the repository already runs |
| `syntactic-pattern` (a code pattern expressible as a syntactic match in any language: a dangerous call, an injection sink, a secret shape, a cross-language invariant) | `syntax-pattern-rule` | build hand-off: a rule for the pattern matcher the repository already runs |
| `structure` (dependency direction, layering, namespace-to-layer naming, forbidden references) | `architecture-test` | build hand-off: a test written with the repository's own architecture-test library |
| `process` (commit shape, file placement, generated-file freshness, session behavior: anything observed at tool-call or commit time rather than in source) | `action-guard` | the `harness-config` plugin's automation-gaps audit when enabled; otherwise record the candidate and stop |
| `design-judgment` (readability, correctness reasoning, prose quality) and `unclassified` | `automated-review` | none; the finding stays a review-time judgment |

An invariant a syntactic match can decide is `syntactic-pattern`, whatever the language; one that
needs to resolve types or symbols is `semantic-invariant`. Neither class is tied to an ecosystem.

## Lookup sections

Three sections, keyed the way [the class ladder](../actions/findings.md#2-derive-the-class) reads
them: exact rule id first, then the rule family the id belongs to, then the dimension heading the
row sat under. A row found here names an existing detector or a settled answer, so it fixes the
rung: no stronger rung is walked.

### Rule-id rows (exact match)

The one id form the detector-findings contract allows is `<plugin>/<skill>/rule-<slug>`, so a
match here is byte-exact on the whole id.

Every hand-off cell below reading "already deterministic: keep the `<plugin>:<skill>` detector" is
gated on that plugin still being enabled in the consuming repo; where it is not, the finding has
no deterministic rung there and falls back to `automated-review`, a review-time judgment, until the
detector is enabled again. The same gate and the same fallback bind the rule-family rows.

| Rule id | Class | Rung | Hand-off | Basis |
|---|---|---|---|---|
| `mutation-testing/audit/rule-survivor-productive` | `design-judgment` | `automated-review` | none | the remedy is a covering test whose assertion is a judgment about the code's contract, which no check can state for you |
| `mutation-testing/audit/rule-survivor-unclassified` | `design-judgment` | `automated-review` | none | the row exists because the classification itself was unresolved, so no deterministic rung can be argued for it |
| `mutation-testing/audit/rule-survivor-arid` | `design-judgment` | `automated-review` | none | aridity is a judgment about whether the node is worth testing at all |
| `mutation-testing/audit/rule-survivor-equivalent` | `design-judgment` | `automated-review` | none | equivalence is undecidable in general, so a check that claimed it would be asserting something it cannot know |
| `testing/audit/rule-zero-assertion` | `defined-diagnostic` | `analyzer-pack-rule` | build hand-off: the test-framework analyzer pack already in the project | an assertion-free test body is a whole-method syntactic shape, which is what a test-framework analyzer pack is for; the work is enabling or raising a diagnostic, not writing one |
| `testing/audit/rule-recomputed-expectation` | `semantic-invariant` | `custom-analyzer` | build hand-off (see the class table) | deciding an expected value was recomputed from the code under test needs the semantic model to resolve both sides to the same symbol, which no pack diagnostic states |
| `testing/audit/rule-mock-only-oracle` | `semantic-invariant` | `custom-analyzer` | build hand-off (see the class table) | whether the oracle reaches only mocks is a property of which symbols the assertions touch, again a semantic-model question, and over the project's own mocking library |
| `testing/audit/rule-inert-assertion` | `defined-diagnostic` | `analyzer-pack-rule` | build hand-off: the test-framework or linter pack already in the project | the test's language has a pack diagnostic for an assertion whose result is never checked, so the work is enabling or raising it, not writing one. When choosing it, read the pack's own rule page live. Revisit the mapping when `testing:audit` changes what `rule-inert-assertion` matches |
| `testing/audit/rule-constant-restatement` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `testing:audit` detector | the producing detector is itself the deterministic check, a pattern over the equality's two sides, so the cheapest rung is the one already running |
| `testing/audit/rule-source-text-read` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `testing:audit` detector | as above |
| `testing/audit/rule-conditional-assertion` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `testing:audit` detector | as above |
| `testing/audit/rule-recomputed-derived` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `testing:audit` detector | as above |
| `testing/audit/rule-snapshot-only` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `testing:audit` detector | as above |
| `testing/audit/rule-weak-oracle` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `testing:audit` detector | as above |
| `testing/audit/rule-flaky-passes-suite` | `defined-diagnostic` | `analyzer-pack-rule` | already deterministic: keep the `testing:audit` detector | no analyzer pack reads Playwright `retries` against `failOnFlakyTests` (judgment), so the detector's config read stays the check |
| `testing/audit/rule-only-not-forbidden` | `defined-diagnostic` | `analyzer-pack-rule` | build hand-off: the project's own linter configuration | the test framework's linter plugin defines a diagnostic for a focused test, so the work is enabling it in the configuration the project already runs. When enabling it, read the plugin's own rule page live. Revisit the mapping when `testing:audit` changes what `rule-only-not-forbidden` matches |
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

| Family prefix | Class | Rung | Hand-off | Basis |
|---|---|---|---|---|
| `mutation-testing/audit/` | `design-judgment` | `automated-review` | none | every rule in this family reports a surviving mutant, whose remedy is a test whose assertion is judgment |
| `testing/audit/` | `semantic-invariant` | `custom-analyzer` | build hand-off (see the class table) | the family's rules are properties of a test's oracle in whatever language the test is written; the family default takes the semantic-model rung, and an individual rule a pack already covers is listed above |
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
| `security` | `syntactic-pattern` | `syntax-pattern-rule` | the recurring security findings a check can catch are sink and secret shapes, which a syntactic matcher expresses in any language |
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

What the proposal's install step says, for every input.

Every proposed check or rule states its **existing violations**: how many places in the current
tree already break it, and how they were counted (the check run over the tree, or a search for the
same pattern when the check cannot run or for an instruction or other rung with no check, saying
which). When neither can be taken, say so. Existing violations
teach the old way to whoever copies them, so the proposal offers their cleanup in the same change,
carried out by `/implementation:implement`. One rule chooses between cleanup and ratchet: offer the
cleanup when every existing violation can be fixed in the change that lands the rule, as one
reviewable pull request with no fix needing a design decision. Otherwise, or when the count is
unknown, a counting rung (`editorconfig-severity`, `analyzer-pack-rule`, `custom-analyzer`,
`syntax-pattern-rule`, `architecture-test`) with the ratchet offer on ends with it: once the rule
exists, the count goes to `/toolchain:ratchet` and the cleanup follows as its own work. A zero count
lands the rule.

Every checking rung below ends in the build hand-off (see the opening of this file), except
`action-guard` and a rung whose producing detector already is the check: the rung, the check to
prove, and the requirement that the check's message names the fix (the ladder's guardrail criterion
4), with `/implementation:implement` named as the builder. The check is the repository's own, built
in the tooling it already runs; when that tooling is visible in the tree (a config file, a rules
directory, a test project), name it.

- **`make-impossible`**: name the type, data structure or API whose shape lets the invalid state
  exist, and the change that would remove it. Hand it to `/architecture:improve` when that skill is
  available, otherwise to `/planning:design`.
- **`shared-helper`**: name the helper and the lint or check that fails a caller who bypasses it.
- **`formatter`**: name the format command, the `fix-cmd` of the ecosystem record the rule's files
  fall under, and the format setting it reads that holds the rule. The check runs that command and
  then fails when the tree changed. Existing violations take the cleanup offer, never the ratchet:
  running the command over the tree fixes every one.
- **`editorconfig-severity`**: name the setting and the file; no plugin is involved.
- **`analyzer-pack-rule`**: name the diagnostic id and the config file that raises its severity.
  Where the producing detector already is the deterministic check, the next step is to keep it.
- **`custom-analyzer`**: name the invariant the analyzer decides and the symbols or types it
  resolves, in any language whose compiler or linter can run one. The analyzer ships with its own
  valid and invalid rule tests and states what it does not catch
  ([adding-a-team-rule.md](adding-a-team-rule.md#a-custom-rule-ships-with-its-tests)).
- **`syntax-pattern-rule`**: name the pattern to match and the languages it covers. The rule ships
  with its own valid and invalid rule tests and states what it does not catch, as above.
- **`architecture-test`**: name the modules or layers and the reference the test forbids, read from
  the boundary rules the ladder's "Where boundary rules live" lists.
- **`action-guard`**: `/harness-config:audit-automation-gaps hooks` when that plugin is enabled,
  presenting the proposal as a candidate; otherwise the proposal records the candidate with its
  frequency, incident history and the enforcement already covering it.
- **`automated-review`**: a `REVIEW.md` line, for a rule only a reviewer applies or a change to how
  severe a finding is. Say that no check catches it.
- **`instruction`**: a `CLAUDE.md`, `AGENTS.md` or rules-file line, placed by section 3.

## Record line

A proposal for a codebase, static-analysis or verification rung holds the literal line the pull
request that lands it carries in its body, so `/corrections:codify count-checks` counts it once it
merges:

```text
Codifies: #123 rung=architecture-test blocking
```

- **Source**: `#<n>`, the issue or the pull request whose review raised the correction, or the
  literal `session` when neither exists. Never a URL.
- **Rung**: the current rung id the proposal picked, never an alias.
- **Blocking or advisory**: `blocking` when the check fails the change (a hook, a required CI check,
  a lint at error level), else `advisory`. A `make-impossible` record is always `blocking`, and its
  proposal names the type, data structure or API to change ("Next step per rung" above).
- **Shape**: the whole line matches
  `^Codifies: (#[1-9][0-9]*|session) rung=<rung id> (blocking|advisory)$`. It sits at column 0 on a
  line of its own, not in a list item, an indented line or a quote, and is at most 72 characters
  long so the squash commit's wrap cannot split it. It is a body line, not a git trailer.
- **Promotion**: when an advisory check later becomes blocking, the change that makes it blocking
  carries the line with `blocking`, the same rung, and as its source `#<p>`, the pull request that
  landed the advisory record (the `(#<p>)` that commit's subject ends with). `count-checks` then
  moves the check from the advisory column to the blocking one and counts it once, whatever the
  advisory record's own source was, `session` included. A blocking line whose source is any other
  `#<n>` is a new check, even when an advisory record names the same `#<n>` and rung. An advisory
  record whose commit subject ends with no `(#<p>)` cannot be promoted. Identical lines in one
  commit message count once, so each promotion of a record with the same source `#<p>` and rung
  needs its own commit. A blocking line whose advisory record's commit is later reverted stands as a
  new blocking check.
- **Work filed as an issue**: the proposal also gives the task-list item for the issue's done-when
  list, which quotes the line in a code span and names the pull request body:

  ```markdown
  - [ ] The PR body carries `Codifies: #123 rung=architecture-test blocking`.
  ```

  The issue lane copies a line from such an item into its pull request body, the way it copies a
  `Refs:` line, and never from the run's own text.
