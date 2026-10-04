---
description: "Audit the test suite for tests that cannot fail or check little. A deterministic script detects assertion-free bodies, self-identical or recomputed expectations, mock-only oracles, assertions that never run or sit only in a branch, weak or snapshot-only oracles, and constant or source-text change detectors across JS/TS, Python, C#, Bash, PowerShell and Go, reports with a coverage denominator, gates fail-closed via --check, and opt-in persists findings for the review fix pass. Use when: the user wants tests that cannot fail found (tautological, vacuous, or assertion-free tests, or tests that pass but prove nothing), a Playwright suite that cannot fail found (retries with no `failOnFlakyTests`, an unguarded `test.only`), a CI gate on can't-fail tests, or findings persisted for the fix pass. Flags: `--check` (exit-code gate), `--strict` (also gate mock-only-oracle and the Playwright config findings), `--persist-findings`. Read-only on the suite: findings propose repairs; nothing edits or deletes a test."
argument-hint: "[--check] [--strict] [--persist-findings] [--file <path>]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: test
  summary: Detect tests that cannot fail. Report, gate, or persist
---

## Purpose

A test that cannot fail is a false coverage claim: it reports green whatever the code does. This
skill runs a **deterministic script detector** over the suite. It does not execute tests or judge membership, but reports every test the rules catch, with a coverage denominator so "no findings"
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
  `*.test.sh`. That rule is deliberately absent here: this skill owns assertions in those files,
  and its `bash-harness` findings are advisory (never gating `--check` without `--strict`).
- The **repair queue** is out of scope: findings propose an assertion (repair, not
  pruning: deleting a useless test removes the false claim and the coverage together); applying
  repairs belongs to the remediation lanes.

## Rules

Rule ids are the qualified detector-findings form; thresholds are fixed per rule, and every finding
states the fired condition in the run's own values.

| Rule id | Detects | Tier | Confidence | Gates `--check` | Gates `--check --strict` |
|---|---|---|---|---|---|
| `testing/audit/rule-zero-assertion` | a runnable test body with no assertion token | IMPORTANT | `high` | yes | yes |
| `testing/audit/rule-recomputed-expectation` | an equality whose actual and expected sides are the identical expression; a deliberate determinism check `f(x) == f(x)` still fires and is marked `cant-fail-ok: determinism contract` | IMPORTANT | `high` | yes | yes |
| `testing/audit/rule-mock-only-oracle` | a mock-constructing test whose every assertion is a mock-interaction assertion | IMPORTANT | omitted | no | yes |
| `testing/audit/rule-flaky-passes-suite` | a Playwright config with retries and `failOnFlakyTests` absent or literal `false`, so a test passing on a retry leaves the run green | IMPORTANT | omitted | no | yes |
| `testing/audit/rule-only-not-forbidden` | a Playwright config with `forbidOnly` absent or literal `false`, so a committed `test.only` shrinks the suite to one test | IMPORTANT | omitted | no | yes |
| `testing/audit/rule-inert-assertion` | an assertion that never evaluates: an unawaited async matcher, a Python tuple assert or mock attribute, a bare `.Should();`, a constant C# oracle (`Assert.True(true)`, `Assert.NotNull(typeof(T))`), a bats `run` nothing checks | IMPORTANT | `high` | report-only in Release 1 | report-only in Release 1 |
| `testing/audit/rule-constant-restatement` | a constant, or a literal the test bound, compared to a literal with no call before it | SUGGESTION | omitted | report-only in Release 1 | report-only in Release 1 |
| `testing/audit/rule-source-text-read` | a tracked non-test source file read by a static path and searched as text | SUGGESTION | omitted | report-only in Release 1 | report-only in Release 1 |
| `testing/audit/rule-conditional-assertion` | every assertion inside an `if`, a `catch` or a loop over a computed result, with no `else` and no length check | IMPORTANT | omitted | report-only in Release 1 | report-only in Release 1 |
| `testing/audit/rule-recomputed-derived` | an expected value rebuilt from the call's own arguments with an operator or aggregate (`reduce`, `sum(`, `a + b`); property-test files and Playwright are exempt | SUGGESTION | omitted | report-only in Release 1 | report-only in Release 1 |
| `testing/audit/rule-snapshot-only` | every assertion is a snapshot call ("snapshot is the only oracle: review it as code"); an image comparison never counts | SUGGESTION | omitted | report-only in Release 1 | report-only in Release 1 |
| `testing/audit/rule-weak-oracle` | every assertion is a weak matcher (`toBeDefined`, `is not None`, `Assert.NotNull`) or an over-broad exception check (`toThrow()`, `pytest.raises(Exception)`) | SUGGESTION | omitted | report-only in Release 1 | report-only in Release 1 |

- **`Tier` is looked up from each rule's row in the detector-findings severity crosswalk** (the
  contract cited under Persisting findings): IMPORTANT for the rules whose test cannot fail on the
  path they flag, SUGGESTION for the five whose test can fail (change detectors, derived
  expectations, snapshots, weak oracles). The argument for each mapping lives in the crosswalk
  row, not here; a per-finding tier choice is exactly what the rule-keyed lookup forbids.
- **The seven report-only rules print, count and persist, and never gate `--check`, `--strict`
  included**, until a precision run shows them free of false positives. The coverage block and the
  `--check` note count them apart.
- **`mock-only-oracle` omits `Confidence` and is advisory by default.** The pattern match is certain;
  its defect-hood is not. Deliberate interaction-style (London-school) tests are the known benign
  case. Per the detector-findings contract the field is `high` or omitted, never `low`.
- **The two config rules omit `Confidence` and are advisory for the same reason.** The read is
  mechanical; defect-hood is the team's policy call. Each decline names the evidence it required and
  is counted; a config whose object literal the engine cannot anchor is enumerated and not examined.
- **Detection bias: every heuristic errs toward not firing.** Assertion tokens match generously (a
  helper named `assertValidSum` or `checkInvariant` counts), strings/comments are masked first,
  skipped tests are not judged. A test that calls a function defined in the same file, bare or on
  `self`/`this`/`cls`, whose own body asserts, throws or rejects is not a zero-assertion finding
  (a method call resolves to the test's own class when it defines the name),
  nor is one whose helper calls such a function, to any depth. A bats test whose last line is
  a standalone `! cmd` asserts through it. A missed defect costs one finding; a false positive costs the
  detector its audience.

## Running the detector

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/cant-fail-scan.sh"            # report + denominator
bash "${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/cant-fail-scan.sh" --check    # gate: exit 1 findings, 2 gap, 0 clean
bash "${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/cant-fail-scan.sh" --findings # findings file on stdout
bash "${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/cant-fail-scan.sh" --file <path> # one test file, any mode above
```

Scan root: the current repo's git toplevel (or `$CANT_FAIL_SCAN_ROOT` to narrow/point explicitly,
a supported operator lever). Ecosystems: JS/TS (`*.test.*`/`*.spec.*`: Jest, Vitest, node:test,
Playwright), Python (`test_*.py`/`*_test.py`: pytest, unittest), C# (`*Test.cs`/`*Tests.cs`,
Reqnroll `*StepDefinitions.cs`, `UnitTest*.cs`: xUnit, NUnit, MSTest), Bash (`*.test.sh`
harnesses, `*.bats`), PowerShell (`*.Tests.ps1`, Pester) and Go (`*_test.go`), each defined by an
adapter file in `adapters/`.

When the invocation passes `--file <path>`, forward it to the script's `--file` mode: it scans that
one file, and its coverage block's `adapter:` line names the adapter that claims it, or `adapter: none (...)`
with the reason. `/mutation-testing:audit --exercised` reads that line to tell a test file from a
source file.

Present the script's findings and its coverage block as reported, the denominator is what makes a
clean report a claim rather than an absence. A run that examined 0 test files says so and is never
presented as a clean bill.

## Gate mode (`--check`). Fail closed

The machine-checkable gate the [liveness-assertion contract](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/liveness-assertion/README.md)
"Core contract" fail-loud limb requires of an advisory surface's gating form:

- exit **1**, a gating rule fired (`zero-assertion`, `recomputed-expectation`; `--strict` adds
  `mock-only-oracle` and both config rules). **`--strict` is one switch for all three**, no finer grain.
  The seven report-only rules never set exit 1, `--strict` included.
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
2. Resolve the destination per the contract "Where the file goes": the current branch's findings
   directory in the memory slice (`<memory_dir>/reviews/<branch-slug>/`, `.work/` unless the project's
   instructions declare another root), and honor the **self-ignore guard** including its
   root-equivalent-root rule.
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
  Audit stays repair, not pruning: `/testing:cleanup` rewrites, quarantines and, with the user's
  yes per item, deletes tests behind a mutation gate.
- **Execute the suite**. `/toolchain:check` runs tests; `mutation-testing:audit` executes mutants.
- **Judge skips in bash `*.test.sh`**, the discriminating-skip repo gate owns that shape.
- **Read any runner config but Playwright's JS/TS one.** Vitest's `retry` and `allowOnly`, Jest, and
  the other runners' equivalents are out of scope v1, as are Playwright's C# and Python bindings,
  which configure the runner in their own surfaces rather than in a config object read here.
- **Write anything on bare invocation**. Persisting is only ever behind `--persist-findings`.

## Next

- A finding names a test that needs a real assertion: `/testing:write`.
- Findings cover a folder of low-value tests to rewrite or prune: `/testing:cleanup <folder>`.
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
