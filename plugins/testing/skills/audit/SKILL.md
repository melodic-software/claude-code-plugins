---
description: "Audit the test suite for tests that cannot fail, a deterministic script detects assertion-free test bodies, self-identical (recomputed-expectation) assertions, and mock-only oracles across JS/TS, Python, and C#, reports with a coverage denominator, gates fail-closed via --check, and opt-in persists a findings file the review fix pass consumes. Use when: the user wants tests that cannot fail found (tautological, vacuous, or assertion-free tests, or tests that pass but prove nothing), a Playwright suite that cannot fail found (retries configured with no `failOnFlakyTests`, a committed `test.only` that no `forbidOnly` guards), a CI gate on can't-fail tests, or the audit's findings persisted for the fix pass. Flags: `--check` (exit-code gate), `--strict` (gate mock-only-oracle and the Playwright config findings too), `--persist-findings` (write the findings file the review fix pass consumes). Read-only on the suite: findings propose repairs; nothing edits or deletes a test."
argument-hint: "[--check] [--strict] [--persist-findings]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: test
  summary: Detect tests that cannot fail. Report, gate, or persist
---

## Purpose

A test that cannot fail is a false coverage claim: it reports green whatever the code does. This
skill runs a **deterministic script detector** over the suite. It does not execute tests or judge membership, but reports every test the rules v1 catch, with a coverage denominator so "no findings"
is never confused with "scanned nothing".

A second layer reads the **Playwright runner config**: a suite whose runner is configured to swallow
a failure cannot fail whatever its test bodies assert, so the same detector reports that shape under
the same rule ids, gate, and findings file, with its own denominator of configs enumerated.

Boundaries, each an incumbent this skill deliberately does not duplicate:

- **`mutation-testing:audit`** proves dynamically that tests fail to detect change. It executes
  mutants, costs real runtime, and judges survivors. This skill is the static complement: cheap
  AST-level detection of tests that cannot fail *by construction*. Complements, not rivals.
- **`check-discriminating-test-skips.sh`** (this marketplace repo's own CI gate) owns the fourth
  can't-fail shape, a skip vacating the only discriminating assertion of a case group, for bash
  `*.test.sh`. That rule is deliberately absent here; bash test files are out of scope v1.
- The **repair queue** is out of scope: findings propose an assertion (repair, not
  pruning: deleting a useless test removes the false claim and the coverage together); applying
  repairs belongs to the remediation lanes.

## Rules v1

Rule ids are the qualified detector-findings form; thresholds are fixed per rule, and every finding
states the fired condition in the run's own values.

| Rule id | Fires when | Threshold | Confidence | Gates `--check` |
|---|---|---|---|---|
| `testing/audit/rule-zero-assertion` | a runnable test body contains no assertion token | 0 assertion tokens | `high` | yes |
| `testing/audit/rule-recomputed-expectation` | an equality assertion's actual and expected sides are the identical expression, the expected value is recomputed by the code under test rather than stated | >= 1 self-identical equality assertion | `high` | yes |
| `testing/audit/rule-mock-only-oracle` | a mock-constructing test whose every assertion is a mock-interaction assertion, none on a real collaborator | 100% of assertions are mock-interaction | omitted | only with `--strict` |
| `testing/audit/rule-flaky-passes-suite` | a Playwright config configures retries while `failOnFlakyTests` is absent or literal `false`, so a test that fails and passes on a retry leaves the run green | `retries` > 0 or an expression, `failOnFlakyTests` absent or literal `false` | omitted | only with `--strict` |
| `testing/audit/rule-only-not-forbidden` | a Playwright config leaves `forbidOnly` absent or literal `false`, so a committed `test.only` shrinks the suite to one passing test instead of failing the run | `forbidOnly` absent or literal `false` | omitted | only with `--strict` |

- **`Tier` is looked up from each rule's row in the detector-findings severity crosswalk** (the
  contract cited under Persisting findings). IMPORTANT on every row, flat per producer. The
  argument for each mapping lives in the crosswalk row, not here; a per-finding tier choice is
  exactly what the rule-keyed lookup forbids.
- **`mock-only-oracle` omits `Confidence` and is advisory by default.** The pattern match is certain;
  its defect-hood is not. Deliberate interaction-style (London-school) tests are the known benign
  case. Per the detector-findings contract the field is `high` or omitted, never `low`.
- **The two config rules omit `Confidence` and are advisory for the same reason.** The read is
  mechanical; defect-hood is the team's policy call. Each decline names the evidence it required and
  is counted; a config whose object literal the engine cannot anchor is enumerated and not examined.
- **Detection bias: every heuristic errs toward not firing.** Assertion tokens match generously (a
  helper named `assertValidSum` or `checkInvariant` counts), strings/comments are masked first,
  skipped tests are not judged. A missed defect costs one finding; a false positive costs the
  detector its audience.

## Running the detector

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/cant-fail-scan.sh"            # report + denominator
bash "${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/cant-fail-scan.sh" --check    # gate: exit 1 findings, 2 gap, 0 clean
bash "${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/cant-fail-scan.sh" --findings # findings file on stdout
```

Scan root: the current repo's git toplevel (or `$CANT_FAIL_SCAN_ROOT` to narrow/point explicitly,
a supported operator lever). Ecosystems v1: JS/TS (`*.test.*`/`*.spec.*`), Python
(`test_*.py`/`*_test.py`), C# (`*Test.cs`/`*Tests.cs`).

Present the script's findings and its coverage block as reported, the denominator is what makes a
clean report a claim rather than an absence. A run that examined 0 test files says so and is never
presented as a clean bill.

## Gate mode (`--check`). Fail closed

The machine-checkable gate the [liveness-assertion contract](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/liveness-assertion/README.md)
"Core contract" fail-loud limb requires of an advisory surface's gating form:

- exit **1**, a gating rule fired (`zero-assertion`, `recomputed-expectation`; `--strict` adds
  `mock-only-oracle` and both config rules). **`--strict` is one switch for all three**, no finer grain.
- exit **2**, the scan could not run, could not fully read its inputs (unresolved root, unreadable
  test files, walk errors), or examined **0 test files**, a wrong or empty scan root and a healthy
  suite must not share an exit code. A config is not a test file, so a tree of configs alone still
  exits 2 and the message names the config findings it reported. **An unread input is never a clean
  one.**
- exit **0**. Only a fully read, finding-free scan of at least one test file.

## Persisting findings (`--persist-findings`)

Bare invocation reports and stops, the `audit` verb's read-only contract. Under the explicit
`--persist-findings` override, also write the findings file the `review:fanout` `fix` action
consumes:

1. **Read the producer contract before the first write**.
   <https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/detector-findings/README.md>.
   It owns the shape's authority, where the file goes, the producer-computed fields, the coexistence
   obligations, the self-ignore guard, and what a minimal producer may omit. Where the two disagree,
   the contract wins and this file is the defect. If it cannot be fetched, do not write. Report and
   stop; a guessed destination reports success while the consumer never scans that path.
2. Resolve the destination per the contract "Where the file goes": run the **whole rung order**, take
   the **non-interactive collapse** where this context cannot ask or persist config, and honor the
   **self-ignore guard** including its invalid-root rule.
3. Generate the content with `cant-fail-scan.sh --findings` (it computes `branch:` verbatim from git,
   `date:` at write time, per-rule `Tier`/`Confidence`, repo-relative `Location`, cell escaping, and
   the `## Surfaces` coverage line; it omits `tier:`, `## By dimension`, and `## Unparsed`. No
   analogue, omit rather than fabricate). Write it to
   `<resolved-dir>/${TS}-cant-fail-tests.md` with `TS="$(date -u +%Y%m%dT%H%M%SZ)"`.
4. **Never overwrite an existing path**. Take `-2`, `-3`… (smallest free integer >= 2).
5. A run that examined test files and found nothing **still persists**: the empty table plus
   `## Surfaces` is coverage the consumer merges. A run that examined nothing writes nothing. The
   script already refuses `--findings` there.
6. **Re-runs write what they currently find; never replay** a previous file's rows.

## Exemptions

A deliberate case is recorded in-file: `cant-fail-ok: <reason>` on the test's declaration line, the
line above it, or inside the body, the same recorded-decision shape as the repo gate's
`discriminating-skip-ok`. In a Playwright config it is file-scoped: one `cant-fail-ok:` anywhere in
the file suppresses every config finding. Exemptions are counted in the coverage block, never silent.

## What this skill does NOT do

- **Edit, repair, or delete tests.** Findings propose an assertion; the repair itself is the
  remediation lanes' work (`/testing:write` for authoring, the review fix pass for applying).
- **Execute the suite**. `/toolchain:check` runs tests; `mutation-testing:audit` executes mutants.
- **Audit bash `*.test.sh`**, the discriminating-skip repo gate owns that shape.
- **Read any runner config but Playwright's JS/TS one.** Vitest's `retry` and `allowOnly`, Jest, and
  the other runners' equivalents are out of scope v1, as are Playwright's C# and Python bindings,
  which configure the runner in their own surfaces rather than in a config object read here.
- **Write anything on bare invocation**. Persisting is only ever behind `--persist-findings`.

## Next

- A finding names a test that needs a real assertion: `/testing:write`.
- Findings are persisted with `--persist-findings`: `/review:fanout fix`.

## Gotchas

- **Interaction-style tests trip `mock-only-oracle` by design**. That is why it is advisory in
  `--check` and carries no `Confidence`. A team that asserts interactions deliberately annotates
  `cant-fail-ok:` or leaves `--strict` off; a team that considers them defects gates with `--strict`.
- **Generous assertion tokens buy false-negative risk**: a test whose only "assertion" is a helper
  named `checkout()` is suppressed by the `check` token. That is the chosen direction; do not
  tighten the token list to chase recall at precision's expense.
- **`recomputed-expectation` v1 is the decidable core**. Textually identical actual/expected on one
  line (chains spanning lines are deliberately not matched, and only the first `expect` per line is
  examined). `x = f(a); assert x == f(a)` and C#'s generic `Assert.Equal<T>(a, a)` are the same
  defect and are not detected.
- **The JS regex-literal masker triggers only after an operator or opening delimiter**, never after
  an identifier, so a regex directly after `return` is not masked. Wrongly reading division as a
  regex would mask real code, which is the worse direction. The known cost of that narrow set is a
  premature-block-closure false positive when an unmasked regex after `return` contains a brace
  (e.g. `return /}/;` inside a test). `brace_delta` treats the `}` as code and closes the test
  before later assertions, so `rule-zero-assertion` can fire on a body that still has assertions.
- **Skips are honored at both levels**. Test-level (`it.skip`/`x`-prefixed/`@skip`/`[Fact(Skip=…)]`)
  and suite-level (<!-- spellchecker:off -->`xdescribe`<!-- spellchecker:on -->/`describe.skip`/`context.skip`/`suite.skip`): a test that does not
  run is not judged.
- **Fixture corpora under `evals/fixtures/` are pruned**, a detector's planted-defect fixtures are
  not the consumer's defects. Point `$CANT_FAIL_SCAN_ROOT` at one explicitly to scan it.
- **Platform-conditional skips are outside the detector's reach.** A visible skip is not an
  assertion-free body, so a case that only another platform executes is neither a finding nor
  coverage here; a green local run is not evidence about it.
- **Four paths turn retries or the guards on with no config key to read.** CLI `--retries <n>`
  overrides the project-level and top-level value, and `--fail-on-flaky-tests` and `--forbid-only`
  satisfy the intent from the command line (basis: Playwright's `program.ts` options and the
  test-retries page's `npx playwright test --retries=3` example; as-of v1.63.0, read 2026-09-11;
  recheck on a release note naming a retries or forbid-only flag). A
  `test.describe.configure` call sets `retries` "for a specific group of tests or a single file" from
  inside a test file (basis: playwright.dev/docs/test-retries; as-of 2026-09-11; recheck when that
  page drops or renames the form). An absent `retries` is a counted decline, never proof of none.
- **`retries` fires on an expression while the two boolean guards pass on one.** `retries` defaults
  to `0` and a literal `0` is honored wherever it is written, so only a provable zero puts the flaky
  shape out of reach and `retries: process.env.CI ? 2 : 0` fires (basis: `config.ts`'s
  `takeFirst` chain for retries and the TestConfig reference, "By default failing tests are not
  retried"; as-of v1.63.0, read 2026-09-11; recheck when a release note changes the default or
  `takeFirst` changes its skip test). `forbidOnly: !!process.env.CI` is the documented scaffold
  idiom, so any non-`false` expression passes (basis: playwright.dev/docs/test-configuration
  and the `create-playwright` scaffold; as-of 2026-09-11; recheck when either changes the idiom).
- **A mixed per-project `retries` is read imprecisely, the one place the rules over-fire.** `retries`
  is read at depth 1 and inside `projects[]` entries only, and a project's literal `0` turns retries
  off for that project, so a top-level `retries: 2` that every `projects[]` entry overrides with `0`
  still yields one finding (basis: the same `takeFirst` order; as-of v1.63.0, read
  2026-09-11; recheck when retries precedence changes). Record a deliberate case with `cant-fail-ok:`,
  file-scoped in a config: one annotation suppresses both rules there, each suppression counted,
  while the test-body rules keep declaration-line scoping.
- **A config-only tree reports and stops.** Config findings print wherever they are found, but the
  exit-2 rule for 0 examined test files is unchanged, so a tree with no test file neither gates nor
  persists them; the `--check` message and the `--findings` refusal both say so.
- **The walk probes `playwright.config.` with `.ts`, `.js`, `.mts`, `.mjs`, `.cts`, `.cjs` in one
  directory and reads the first**, the runner's own probe order, counting the rest as shadowed
  (basis: `configLoader.ts` `resolveConfigFileFromDirectory` and the test-CLI doc's "in
  the current directory"; as-of v1.63.0, read 2026-09-11; recheck when that array or the documented
  discovery changes). A `playwright-ct.config.*` or a `--config` file under another name is not probed.
- **`failOnFlakyTests` needs Playwright 1.52 or later**, and the `--fail-on-flaky-tests` CLI flag it
  mirrors covers 1.45 and later (basis: the TestConfig page's "Added in: v1.52" and the
  1.52 release notes; as-of v1.63.0, read 2026-09-11; recheck on a release note renaming or
  deprecating it). The detector does not read the installed version, so the Action names the floor.
