# Precision runs: can't-fail scanner

Each section records one scan of one repository: what was scanned, every finding's verdict, and
what changed because of the false positives. A false positive becomes a good corpus fixture and an
adapter fix before the section closes.

## This repo, Bash

Scanned 2026-09-28 on `feat/testing-test-scan-hook`: `CANT_FAIL_SCAN_ROOT=. bash
plugins/testing/skills/audit/scripts/cant-fail-scan.sh`, 467 `*.test.sh` files through the
`bash-harness` adapter.

- First pass: 18 `rule-zero-assertion` findings, 0 `rule-recomputed-expectation`.
- Verdicts: 18 false positives, 0 true positives. Each file does check behavior; the adapter missed
  how.
- The phase verifier found 14 files never judged: the Bash lexer lost sync and dropped the file
  silently. Three lexer bugs caused it: `$( )` holding its own quotes inside a double-quoted
  string, `${#x}` read as a comment, and a `<<<` here-string read as a heredoc. After the fixes,
  and a coverage line counting any file whose lexer ends out of sync, all 467 files are judged
  (`files whose lexer lost sync (not judged): 0`).
- True-positive count after the fixes: **0**. The sanity check `grep -c
  'rule-zero-assertion.*\.test\.sh'` over the scan output must equal this number.

| Missed mechanism | Files | Adapter fix | Good fixture |
|---|---|---|---|
| Interpreter held in a variable runs the suite: `"$PYTHON" "$SUITE"`, `"$PY" -c '...assert...'` | 7: `overlap`, `validate-cases`, `observer`, `hop_chain`, `check-code-metrics-config-reference`, `check-contract-clause-coverage`, `check-manifest-duplicate-keys` | delegation `"$(PYTHON\|PY)"` in command position | `python-in-variable.test.sh` |
| Sources the shared `lib/test-harness.sh` | 6: `ai-slop-report`, `sync-context-zone`, `sync-html-escape`, `sync-legacy-statusline-detect`, `sync-spawn-noise`, `sync-unwrap-before-compose` | delegation `test-(helpers\|harness)` | `sources-test-harness.test.sh` |
| Homegrown helpers feed a `FAIL` counter the script exits on | 3: `comment-tooling-probe`, `pr-linkage-mcp-gate`, `gen-hook-filters` | idiom `FAIL"?[[:space:]]*(-eq\|==)[[:space:]]*0` | `failure-counter.test.sh` |
| Runs a PowerShell self-test | 1: `Invoke-Dlss5Mod` | `pwsh` joins the interpreter delegation | `pwsh-selftest.test.sh` |
| Node driver from a heredoc exits on its failure count | 1: `check-loop-closure-helpers` | idiom `process\.exit\([A-Za-z_]*fail` | `node-driver-heredoc.test.sh` |

The two widest entries, the `"$PYTHON"` delegation and the `FAIL` counter idiom, trust the
delegate or counter without reading it, as the existing `source ... test-helpers` entry does. A
script that runs a suite with no real assertions, or keeps a counter it never increments, is
cleared. `bash-harness` stays advisory in Release 1 for this reason.

## This repo, source-text read

Scanned 2026-09-29 on `feat/testing-test-scan-hook`: `CANT_FAIL_SCAN_ROOT=. bash
plugins/testing/skills/audit/scripts/cant-fail-scan.sh`, 744 test files, with the three
report-only rules added. The findings of the five existing rules did not move under gawk or mawk.

- `rule-source-text-read`: 4 findings, 4 true positives, 0 false positives. Each reads one tracked
  source file by a static path and checks its text:

  | Test | Source read | What it checks |
  |---|---|---|
  | `plugins/knowledge/skills/video-digest/extraction/harvesting/analyze-harvested-repos.test.js:103` | `analyze-harvested-repos.js` | no `process.exit(` call in the source |
  | `plugins/claude-ops/hooks/session-event-log.test.sh:294` | `plugins/claude-ops/hooks/session-log-lib.sh` | no `hook-utils` source line |
  | `plugins/guardrails/hooks/abort-boundary.test.sh:247` | `plugins/guardrails/hooks/run-guards.sh` | `PRIME_FILTERS` lists `.hook_event_name` |
  | `plugins/testing/skills/audit/scripts/cant-fail-scan.test.sh` (the eval-coverage case) | `plugins/testing/skills/audit/scripts/cant-fail-scan.sh` | the rule ids the driver emits |

- The count the Sanity Check compares: `CANT_FAIL_SCAN_ROOT=. bash
  plugins/testing/skills/audit/scripts/cant-fail-scan.sh | grep -c 'rule-source-text-read'`
  printed 4 on this run and prints **5** since main added
  `plugins/repo-fleet-hygiene/skills/sync/scripts/sync-fleet.test.sh:116`, a true positive: it seds
  `audit-fleet.sh` for its `SKIP_NAMES` list to check that two copies do not drift, the same
  deliberate consistency check as the eval-coverage case below.
- The rest of the local Bash greps over source paths read through a variable path, a glob or a
  directory walk, which the rule never flags; none needed an adapter fix.
- A later verifier pass found false positives outside this repo. The rule now keeps a read only
  when the same test searches the text (`indexOf`, `toContain`, `in`, `Contains`, `-match`,
  `grep`), and never when the test parses or executes it (`ast.parse`, `exec`, `eval`,
  `vm.run*`, `new Function`). `__testfixtures__` joined the excluded paths. Each false positive
  is a good corpus fixture: an `ast.parse` walk, an `exec` of a script, a `vm.runInNewContext`
  sandbox, a codegen freshness check comparing the whole file, and a codemod reading
  `__testfixtures__`. The four findings above all search the text, so the count stayed 4.
- The eval-coverage case in `cant-fail-scan.test.sh` greps the driver's source for the rule ids it
  emits. It is a true positive by the rule's definition, a searched read of a tracked source file,
  and a deliberate one: a consistency check between two files, not a behavior test.

`rule-constant-restatement` on the same run: 5 findings, 5 true positives, 0 false positives.
`test_spawn_noise.py:63-64` compares two threshold constants to their literals, and
`test_install_state.py:743,746-747` compares `engine.SCHEMA` and two vocabulary constants to
theirs. One false positive surfaced while the rule was built and was fixed before this run: a
shell helper taking its message first (`assert_eq "<message>" "$SHA2" ...`) read the message as
the literal, and `read -r SHA1 SHA2` did not count as assigning `SHA2`. A spaced shell string is
no longer a literal, and `read` and `for` assign every name they list.

`rule-inert-assertion` on the same run: 0 findings.

The same verifier pass fixed false positives in both rules with corpus fixtures.
`rule-constant-restatement` now fires only when the test runs no act step before the assertion:
no call other than an assertion or an import, and in shell no command after the last source
line. It no longer runs in C#, Go or Pester, whose constants are not uppercase (`rules_off` in
those adapters). `rule-inert-assertion` no longer reads a Go `else` branch as the checked one,
fires on a Go log-only branch only when the condition compares a result (`got`, `want`,
`expected`, `actual`), and drops a Pester comparison continued by a backtick or a leading pipe.
The five constant findings above and the zero inert findings did not move.

## This repo, Phase 4b rules

Scanned 2026-09-29 on `feat/testing-test-scan-hook`, the same command over the same 744 test
files. Findings of the five existing rules and the three Phase 4a rules did not move under gawk or
mawk; one 4a finding changed line only, because its test file grew.

| Rule | Findings | True positives | False positives |
|---|---|---|---|
| `rule-conditional-assertion` | 2 | 2 | 0 |
| `rule-recomputed-derived` | 1 | 1 | 0 |
| `rule-snapshot-only` | 0 | 0 | 0 |
| `rule-weak-oracle` | 14 | 14 | 0 |

- `rule-conditional-assertion`: `test_install_state.py:456` asserts only inside `for row in rows:`
  and `if row.surface == SECRET`, so a tree with no secret rows passes; `Test-DiskHealth.Tests.ps1:98`
  asserts only inside `foreach ($v in $result.detail.volumes)`, so no volumes passes.
- `rule-recomputed-derived`: `test_install_state.py:619` expects `"'" + cell` from
  `engine.csv_safe(cell)`, the code's own formula. The contract is stated as that formula, so the
  test is correct today and cannot catch a formula that is wrong in the same way.
- `rule-weak-oracle`: five bare `toThrow()` on a schema parse (`bulk.test.ts:78`,
  `connectors.test.ts:15,19,23,27`) and three bare Pester `Should -Throw`
  (`ConvertFrom-Jsonc.Tests.ps1:144`, `Write-HealthResult.Tests.ps1:55,60`) pass for any error;
  `synthesis-filename.test.js:13` accepts any truthy reason; five not-None or not-empty checks
  (`test_guard_launch_monitor.py:224,344`, `test_babysit_merge.py:655`,
  `Test-DiskHealth.Tests.ps1:98`, `Get-ElevationMatrix.Tests.ps1:15`) are the only oracle. In the
  last five, presence is the stated contract, the known benign case, which is why the rule is a
  SUGGESTION with `Confidence` omitted.
- No false positive surfaced, so no adapter fix was needed. Two fixtures moved while the rules were
  built: a lone `Verify` and a lone `t.assert.snapshot`, kept as good zero-assertion fixtures, are
  snapshot-only by definition and now sit in `bad/` with `expect: rule-snapshot-only`.

## Verifier probes, Phase 4b rules

A verifier's probe files, outside this repo, found six false positives. Each is now a good corpus
fixture; the repo's findings did not move.

| Probe | Rule | Fix | Good fixture |
|---|---|---|---|
| `expect(total(items)).toBe(items.length * 5)` | `rule-recomputed-derived` | an input read only as `.length`, `.Length`, `.Count`, `.size` or `len()` is not an input | `js-vitest/good/vitest-length-invariant.test.ts` |
| `expect(merge(a, b).length).toBe(a.length + b.length)` | `rule-recomputed-derived` | the same | `js-vitest/good/vitest-length-invariant.test.ts` |
| `assert with_id(payload) == {**payload, "id": 1}` | `rule-recomputed-derived` | a `{**x}` or `{ ...x }` spread is not an input, and its `**` is not an operator | `py-pytest/good/test_pytest_length_invariant.py` |
| `pytest.fail("no raise")` in the try, the assertion in the `except` | `rule-conditional-assertion` | `pytest.fail` is an assertion call in `py-pytest` | `py-pytest/good/test_pytest_try_fail.py` |
| `Verify(order)` calling the file's own `Verify` helper | `rule-snapshot-only` | C# `Verify(` is a snapshot only in a file importing a Verify package or marked `[UsesVerify]`, and declaring no `Verify` method | `cs-xunit/good/OrderPricedHelperTests.cs`, `cs-xunit/good/InvoiceVerifyHelperTests.cs` |
| `snapshot = store.save(...)` then `assert store.latest() == snapshot` | `rule-snapshot-only` | `== snapshot` is syrupy only when `snapshot` is a parameter of the test | `py-pytest/good/test_pytest_snapshot_local.py` |

## Three repositories, every rule

Scanned 2026-09-29, whole tree, read-only, no flags: `CANT_FAIL_SCAN_ROOT=<repo> bash
plugins/testing/skills/audit/scripts/cant-fail-scan.sh`. Before is the scanner at the base of this
branch; after is with the fixes below. Every run exited 0 with `walk/read/engine error lines: 0`
and `files whose lexer lost sync (not judged): 0`. Files examined per adapter, of all enumerated:

| Repository | HEAD | Files examined | Per adapter |
|---|---|---|---|
| claude-code-plugins | `8da943138615` (this branch) | 753 | bash-harness 503, js-jest 5, js-vitest 90, pwsh-pester 55, py-pytest 2, py-unittest 98 |
| medley | `4a7c01a14a31` | 486, and 1 Playwright config | bash-harness 256, cs-xunit 136, js-node-test 1, js-playwright 1, js-vitest 86, pwsh-pester 1, py-pytest 5 |
| ci-runner | `18f5366fdb1d` | 65 | go-testing 62, js-node-test 3 |

`bash-bats`, `cs-mstest` and `cs-nunit` have no file in any of the three, so every rule is
unmeasured there.

A rule is measured in an adapter only when its form occurs in that adapter's files (a grep-level
census). With 0 findings where the form never occurs, the rule is **unmeasured** there; `n/a`
means the adapter turns the rule off or has no vocabulary for it.

| Rule | Before | After | True positives | False positives after | Unmeasured |
|---|---|---|---|---|---|
| `rule-zero-assertion` | 53 (ccp 10, medley 42, ci-runner 1) | 2 (ccp 1, medley 1), and ccp 1 exempt | 2 | 0 | none |
| `rule-recomputed-expectation` | 2 (ccp 1, medley 1) | 1 (medley), and ccp 1 exempt | 0 | 0; both are determinism contracts, the annotate case | js-playwright |
| `rule-mock-only-oracle` | 27 (ccp 13, medley 14) | 27 | 27, all benign | 0 | js-jest, js-node-test, js-playwright, py-pytest; bash-harness and go-testing n/a |
| `rule-inert-assertion` | 0 | 0 | 0 | 0 | js-jest, js-playwright |
| `rule-constant-restatement` | 8 (ccp 5, medley 3) | 8 | 8 | 0 | js-jest, js-node-test, js-playwright; C#, Go and Pester n/a |
| `rule-source-text-read` | 7 (ccp 5, medley 2) | 7 | 7 | 0 | js-playwright |
| `rule-conditional-assertion` | 5 (ccp 2, medley 3) | 4 | 4 | 0 | bash-harness n/a |
| `rule-recomputed-derived` | 1 (ccp) | 1 | 1 | 0 | cs-xunit, js-jest, js-node-test; js-playwright and bash-harness n/a |
| `rule-snapshot-only` | 0 | 0 | 0 | 0 | every adapter: no snapshot-library call in any file |
| `rule-weak-oracle` | 14 (ccp) | 14 | 14 | 0 | js-jest, js-playwright; bash-harness n/a |
| `rule-flaky-passes-suite` | 0 | 0 | 0 | 0 | js-playwright: the one config sets no `retries` |
| `rule-only-not-forbidden` | 1 (medley) | 1 | 1 | 0 | none |

Verdicts:

- `rule-zero-assertion` true positives, both no-raise smoke tests: `test_hook_telemetry.py:54` calls
  `emit` and checks nothing; medley `test_config_validation.py:32` loads a TOML file and asserts
  nothing.
- `rule-zero-assertion` false positives, all resolved: ccp `test_hygiene.py:10117`, whose oracle is
  the probe `os.write(2, b"")` raising when fd 2 was left closed, now carries `cant-fail-ok:`. No
  token separates a probe from a no-raise smoke test, and adding `os.write(` or `os.fstat(` to the
  vocabulary would clear real smoke tests. Medley `broker-fanout.test.ts:305,318` await
  `waitForNotificationOnAll`, which returns `pollUntil(...)`, and only `pollUntil` throws; the
  helper rule now follows helper-to-helper calls to any depth, and a base-versus-head re-scan of
  all three repositories under gawk and mawk cleared exactly these two findings.
- `rule-recomputed-expectation`: ccp `test_observer.py:659` and medley `test_lexical.py:94` assert
  `f(x) == f(x)` to pin determinism. The rule keeps firing on that shape, as NUnit2009, testifylint
  `useless-assert` and staticcheck SA4000 do, with no name-based exemption; a deliberate
  determinism contract carries `cant-fail-ok: determinism contract` and is counted as exempt.
  `test_observer.py` carries it; medley's test, in another repository, does not yet.
- The rest are the true positives the earlier sections and the classification record:
  `mock-only-oracle` findings are interaction-as-output tests (patched `os._exit`, spied
  `process.stdout.write`, Pester `Should -Invoke`, NSubstitute `Received`); `conditional-assertion`
  is `test_install_state.py:456`, `Test-DiskHealth.Tests.ps1:98`, medley
  `SectionChunkerTests.cs:55` and `adapters.test.ts:40`; `only-not-forbidden` is medley
  `tests/e2e/playwright.config.ts:13`, run in CI without `--forbid-only`.

The "This repo, Bash" count holds: `grep -c 'rule-zero-assertion.*\.test\.sh'` printed 1 on the
base of this branch, for `plugins/review/tests/pr-explainer-chrome.test.sh`, which main added and
which counts failures and ends `exit "$((FAIL > 0))"`, a false positive. After the idiom fix it
prints **0** again.

False-positive shapes, each a good corpus fixture that fired before its fix:

| Shape | Rule | Findings cleared | Fix | Good fixture |
|---|---|---|---|---|
| `new AnalyzerTest { ... }.RunAsync()` from `Microsoft.CodeAnalysis.Testing` | `rule-zero-assertion` | medley 34 | `cs-xunit` assertion token `CSharp(Analyzer\|CodeFix\|CodeRefactoring\|SourceGenerator)Test<`, which `cs-nunit` and `cs-mstest` inherit, and `}.RunAsync(` in a file that imports the harness (engine prescan) | `cs-xunit/good/AnalyzerHarnessRunAsyncTests.cs` |
| Expression-bodied test calling a same-file helper that asserts | `rule-zero-assertion` | medley 5 | same-file helpers, one level deep, a method call resolved to the test's own class when it defines the name (engine) | `cs-xunit/good/SameFileAssertingHelperTests.cs`, and the `RunAsync(string)` case in `AnalyzerHarnessRunAsyncTests.cs` |
| `self.refused(...)`, `self.roundtrip(...)` on a method that asserts | `rule-zero-assertion` | ccp 6 | the same | `py-unittest/good/test_unittest_self_helper_asserts.py` |
| Module helper calling `check_returncode()` | `rule-zero-assertion` | ccp 1 | the same | `py-pytest/good/test_pytest_helper_check_returncode.py` |
| Awaited helper that rejects on timeout | `rule-zero-assertion` | none here: medley's helper throws one level further down | the same, with throw, raise and reject counting in a helper's body | `js-vitest/good/vitest-poll-helper-rejects.test.ts` |
| Helper returning a second helper that throws | `rule-zero-assertion` | medley 2 | a helper that calls an asserting helper asserts, to any depth; a C# overload that calls its own name counts when another overload asserts, matched by argument count so an overload that only recurses on itself gets no credit | `js-vitest/good/vitest-helper-chain-throws.test.ts`, `cs-xunit/good/InvoiceOverloadDelegatesTests.cs`; bad: `cs-xunit/bad/InvoiceRecursiveOverloadTests.cs` |
| `! cmd` as a bats test's last line | `rule-zero-assertion` | none here: no bats file in the three | the last-line `!` counts as the assertion | `bash-bats/good/bats-config-removed-last-bang.bats` |
| `node:test` helper calling `assert.*` | `rule-zero-assertion` | ci-runner 1 | the same | `js-node-test/good/node-test-helper-asserts.test.cjs` |
| `exit "$((FAIL > 0))"` failure counter | `rule-zero-assertion` | ccp 1 | `bash-harness` idiom for the arithmetic exit | `bash-harness/good/failure-counter-arith-exit.test.sh` |
| Loop over `await Promise.all(<literal array>.map(...))`, on one line or two | `rule-conditional-assertion` | medley 1 | a map over a nonempty array literal, or over a name the test bound to one, is a literal collection | `js-vitest/good/vitest-loop-over-literal-probes.test.ts` |
| `f(x) == f(x)` determinism check | `rule-recomputed-expectation` | none: kept firing, annotated | `cant-fail-ok: determinism contract`; a trailing annotation on a Python `assert` line no longer drops the finding silently | `py-unittest/good/test_unittest_deterministic_call.py`, `py-pytest/good/test_pytest_deterministic_report.py`, each asserted exempt |

The helper rule reads a function's text from its definition to the first code line indented no
deeper than it, and follows only calls that are bare or on `self`, `this` or `cls`: a first cut
that followed `os.write(` to a `write` method elsewhere in `test_hygiene.py`, and ran a helper's
region on past its closing brace into a `beforeAll` that asserts, cleared findings for the wrong
reason. The bad corpus kept every finding under gawk and mawk.

### Blocking candidates

Blocking stays off in this release (D4). A rule qualifies only in the adapters where it was
measured, never where it is unmeasured. `bash-harness` and `bash-bats` are advisory and never gate,
so they are left out below; `bash-harness` zero-assertion is excluded by the spec.

| Rule | Evidence over the three repositories | Adapters measured with 0 false positives | Recommendation |
|---|---|---|---|
| `rule-inert-assertion` | 0 findings, 0 false positives: precision 0/0, never observed firing on a real test | js-vitest, js-node-test, pwsh-pester, py-pytest, py-unittest, cs-xunit, go-testing | qualifies on 0 false positives (A13); confirm with the next run before flipping |
| `rule-conditional-assertion` | 4 true positives, 0 false positives after the literal-map fix | js-vitest, js-node-test, py-pytest, py-unittest, cs-xunit, pwsh-pester, go-testing | qualifies on 0 false positives since this fix; confirm with the next run |
| `rule-mock-only-oracle` | 27 true positives, all benign interaction-as-output tests | js-vitest, pwsh-pester, py-unittest, cs-xunit | 0 false positives, but every hit is benign, so blocking would only force annotations; keep it `--strict` only |
| `rule-weak-oracle` | 14 true positives | js-vitest, js-node-test, pwsh-pester, py-pytest, py-unittest, cs-xunit, go-testing | qualifies on 0 false positives; SUGGESTION tier, and presence checks are its benign case |
| `rule-constant-restatement` | 8 true positives | js-vitest, py-pytest, py-unittest | qualifies on 0 false positives; SUGGESTION tier |
| `rule-source-text-read` | 7 true positives, 6 of them in advisory `*.test.sh`; 1 outside Bash | js-jest, js-vitest, js-node-test, pwsh-pester, py-pytest, py-unittest, cs-xunit, go-testing | qualifies on 0 false positives, on thin non-Bash evidence (n=1); SUGGESTION tier |
| `rule-recomputed-derived` | 1 true positive (n=1) | js-vitest, pwsh-pester, py-pytest, py-unittest, go-testing | qualifies on 0 false positives, n=1; confirm with the next run |
| `rule-only-not-forbidden` | 1 true positive (n=1) | js-playwright (1 config) | qualifies on 0 false positives, n=1; confirm with the next run |

Not candidates: `rule-zero-assertion` (3 false positives left), `rule-snapshot-only` and
`rule-flaky-passes-suite` (unmeasured in every adapter). `rule-recomputed-expectation` already
gates `--check`; its 2 findings are the determinism case the annotation records.

Hook latency on an idle machine is still open: `uptime` load stayed between 9.7 and 13 through this
run, above the idle bar of 8 that `probes.md` sets.
