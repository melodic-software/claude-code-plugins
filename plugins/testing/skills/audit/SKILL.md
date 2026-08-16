---
description: "Audit the test suite for tests that cannot fail — a deterministic script detects assertion-free test bodies, self-identical (recomputed-expectation) assertions, and mock-only oracles across JS/TS, Python, and C#, reports with a coverage denominator, gates fail-closed via --check, and opt-in persists a findings file the review fix pass consumes. Use when: 'audit tests for tautologies', 'find tests that cannot fail', 'assertion-free tests', 'are any of my tests vacuous', 'tautological tests', 'tests pass but prove nothing', 'gate can't-fail tests in CI', 'persist test-audit findings for the fix pass'. Flags: `--check` (exit-code gate), `--strict` (gate mock-only-oracle findings too), `--persist-findings` (write the findings file the review fix pass consumes). Read-only on the suite: findings propose repairs; nothing edits or deletes a test."
argument-hint: "[--check] [--strict] [--persist-findings]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: test
  summary: Detect tests that cannot fail — report, gate, or persist
---

## Purpose

A test that cannot fail is a false coverage claim: it reports green whatever the code does. This
skill runs a **deterministic script detector** over the suite — no test execution, no judgment in
membership — and reports every test the rules v1 catch, with a coverage denominator so "no findings"
is never confused with "scanned nothing".

Boundaries, each an incumbent this skill deliberately does not duplicate:

- **`mutation-testing:audit`** proves dynamically that tests fail to detect change — it executes
  mutants, costs real runtime, and judges survivors. This skill is the static complement: cheap
  AST-level detection of tests that cannot fail *by construction*. Complements, not rivals.
- **`check-discriminating-test-skips.sh`** (this marketplace repo's own CI gate) owns the fourth
  can't-fail shape — a skip vacating the only discriminating assertion of a case group — for bash
  `*.test.sh`. That rule is deliberately absent here; bash test files are out of scope v1.
- The **repair queue** is out of scope this cycle: findings propose an assertion (repair, not
  pruning — deleting a useless test removes the false claim and the coverage together); applying
  repairs belongs to the remediation lanes.

## Rules v1

Rule ids are the qualified detector-findings form; thresholds are fixed per rule, and every finding
states the fired condition in the run's own values.

| Rule id | Fires when | Threshold | Confidence | Gates `--check` |
|---|---|---|---|---|
| `testing/audit/rule-zero-assertion` | a runnable test body contains no assertion token | 0 assertion tokens | `high` | yes |
| `testing/audit/rule-recomputed-expectation` | an equality assertion's actual and expected sides are the identical expression — the expected value is recomputed by the code under test rather than stated | >= 1 self-identical equality assertion | `high` | yes |
| `testing/audit/rule-mock-only-oracle` | a mock-constructing test whose every assertion is a mock-interaction assertion, none on a real collaborator | 100% of assertions are mock-interaction | omitted | only with `--strict` |

- **`Tier` is looked up from each rule's row in the detector-findings severity crosswalk** (the
  contract cited under Persisting findings) — IMPORTANT on every row, flat per producer. The
  argument for each mapping lives in the crosswalk row, not here; a per-finding tier choice is
  exactly what the rule-keyed lookup forbids.
- **`mock-only-oracle` omits `Confidence` and is advisory by default.** The pattern match is certain;
  its defect-hood is not — deliberate interaction-style (London-school) tests are the known benign
  case. Per the detector-findings contract the field is `high` or omitted, never `low`.
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

Scan root: the current repo's git toplevel (or `$CANT_FAIL_SCAN_ROOT` to narrow/point explicitly —
a supported operator lever). Ecosystems v1: JS/TS (`*.test.*`/`*.spec.*`), Python
(`test_*.py`/`*_test.py`), C# (`*Test.cs`/`*Tests.cs`).

Present the script's findings and its coverage block as reported — the denominator is what makes a
clean report a claim rather than an absence. A run that examined 0 test files says so and is never
presented as a clean bill.

## Gate mode (`--check`) — fail closed

The machine-checkable gate the [liveness-assertion contract](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/liveness-assertion/README.md)
"Core contract" fail-loud limb requires of an advisory surface's gating form:

- exit **1** — a gating rule fired (`zero-assertion`, `recomputed-expectation`; `--strict` adds
  `mock-only-oracle`).
- exit **2** — the scan could not run, could not fully read its inputs (unresolved root, unreadable
  test files, walk errors), or examined **0 test files** — a wrong or empty scan root and a healthy
  suite must not share an exit code. **An unread input is never a clean one.**
- exit **0** — only a fully read, finding-free scan of at least one test file.

## Persisting findings (`--persist-findings`)

Bare invocation reports and stops — the `audit` verb's read-only contract. Under the explicit
`--persist-findings` override, also write the findings file the `review:fanout` `fix` action
consumes:

1. **Read the producer contract before the first write** —
   <https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/detector-findings/README.md>.
   It owns where the file goes, the producer-computed fields, coexistence, and what a minimal
   producer may omit. If it cannot be fetched, do not write — report and stop; a guessed destination
   reports success while the consumer never scans that path.
2. Resolve the destination per the contract "Where the file goes": run the **whole rung order**, take
   the **non-interactive collapse** where this context cannot ask or persist config, and honor the
   **self-ignore guard** including its invalid-root rule.
3. Generate the content with `cant-fail-scan.sh --findings` (it computes `branch:` verbatim from git,
   `date:` at write time, per-rule `Tier`/`Confidence`, repo-relative `Location`, cell escaping, and
   the `## Surfaces` coverage line; it omits `tier:`, `## By dimension`, and `## Unparsed` — no
   analogue, omit rather than fabricate). Write it to
   `<resolved-dir>/${TS}-cant-fail-tests.md` with `TS="$(date -u +%Y%m%dT%H%M%SZ)"`.
4. **Never overwrite an existing path** — take `-2`, `-3`… (smallest free integer >= 2).
5. A run that examined test files and found nothing **still persists**: the empty table plus
   `## Surfaces` is coverage the consumer merges. A run that examined nothing writes nothing — the
   script already refuses `--findings` there.
6. **Re-runs write what they currently find; never replay** a previous file's rows.

## Exemptions

A deliberate case is recorded in-file: `cant-fail-ok: <reason>` on the test's declaration line, the
line above it, or inside the body — the same recorded-decision shape as the repo gate's
`discriminating-skip-ok`. Exemptions are counted in the coverage block, never silent.

## What this skill does NOT do

- **Edit, repair, or delete tests.** Findings propose an assertion; the repair itself is the
  remediation lanes' work (`/testing:write` for authoring, the review fix pass for applying).
- **Execute the suite** — `/toolchain:check` runs tests; `mutation-testing:audit` executes mutants.
- **Audit bash `*.test.sh`** — the discriminating-skip repo gate owns that shape.
- **Write anything on bare invocation** — persisting is only ever behind `--persist-findings`.

## Gotchas

- **Interaction-style tests trip `mock-only-oracle` by design** — that is why it is advisory in
  `--check` and carries no `Confidence`. A team that asserts interactions deliberately annotates
  `cant-fail-ok:` or leaves `--strict` off; a team that considers them defects gates with `--strict`.
- **Generous assertion tokens buy false-negative risk**: a test whose only "assertion" is a helper
  named `checkout()` is suppressed by the `check` token. That is the chosen direction; do not
  tighten the token list to chase recall at precision's expense.
- **`recomputed-expectation` v1 is the decidable core** — textually identical actual/expected on one
  line (chains spanning lines are deliberately not matched, and only the first `expect` per line is
  examined). `x = f(a); assert x == f(a)` is the same defect and is not yet detected.
- **Skips are honored at both levels** — test-level (`it.skip`/`x`-prefixed/`@skip`/`[Fact(Skip=…)]`)
  and suite-level (`xdescribe`/`describe.skip`/`context.skip`/`suite.skip`): a test that does not
  run is not judged.
- **Fixture corpora under `evals/fixtures/` are pruned** — a detector's planted-defect fixtures are
  not the consumer's defects. Point `$CANT_FAIL_SCAN_ROOT` at one explicitly to scan it.
