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
  printed **4**.
- The rest of the local Bash greps over source paths read through a variable path, a glob or a
  directory walk, which the rule never flags; none needed an adapter fix.
- A later verifier pass found false positives outside this repo. The rule now keeps a read only
  when the same test searches the text (`indexOf`, `toContain`, `in`, `Contains`, `-match`,
  `grep`), and never when the test parses or executes it (`ast.parse`, `exec`, `eval`,
  `vm.run*`, `new Function`). `__testfixtures__` joined the excluded paths. Each false positive
  is a good corpus fixture: an `ast.parse` walk, an `exec` of a script, a `vm.runInNewContext`
  sandbox, a codegen freshness check comparing the whole file, and a codemod reading
  `__testfixtures__`. The four findings above all search the text, so the count stays **4**.
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
