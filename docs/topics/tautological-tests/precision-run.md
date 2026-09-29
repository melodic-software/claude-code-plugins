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

`rule-constant-restatement` on the same run: 5 findings, 5 true positives, 0 false positives.
`test_spawn_noise.py:63-64` compares two threshold constants to their literals, and
`test_install_state.py:743,746-747` compares `engine.SCHEMA` and two vocabulary constants to
theirs. One false positive surfaced while the rule was built and was fixed before this run: a
shell helper taking its message first (`assert_eq "<message>" "$SHA2" ...`) read the message as
the literal, and `read -r SHA1 SHA2` did not count as assigning `SHA2`. A spaced shell string is
no longer a literal, and `read` and `for` assign every name they list.

`rule-inert-assertion` on the same run: 0 findings.
