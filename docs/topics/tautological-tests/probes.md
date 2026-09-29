# Live probes: test-scan hook

Probes for Release 1 Phase 2. Each records the Claude Code version, how it was run, and what it
showed.

## `if` row matching and hook input (Claude Code 2.1.284, WSL2, 2026-09-28)

Run: `claude -p --model haiku --permission-mode acceptEdits --plugin-dir plugins/testing
--debug-file <log>` in a scratch git repository, with a project `settings.json` that appended each
PostToolUse payload, or a line per matching `if` row, to a file.

- A non-matching path starts nothing. A Write to `src/app.ts` logged "Skipping hook due to if
  condition ... not matching" for all 32 testing rows, and no test-scan process ran.
- Basename globs match at any depth: `Write(*.test.ts)` matched `src/deep/x.test.ts` and
  `src/deep/y.test.ts`, `Write(test_*.py)` matched `tests/test_more.py`, and `Write(*Tests.cs)`
  matched `src/MoreTests.cs`. `*_test.go` and `*.Tests.ps1` have no row yet; Phase 3 adds their
  adapters, and the probe is repeated then.
- An `Edit(<glob>)` row does not match a Write call. With `Edit(*.test.ts)` rows only, a Write to
  `x.test.ts` skipped every row. `Write(*.test.ts)` matched the Write and `Edit(*.test.ts)` matched
  the Edit of the same file. `gen-hook-filters.sh` therefore emits a Write row and an Edit row per
  glob.
- The hook input carries `agent_id` for a subagent's Write (`a98ff69ea957c32d8`) and none for the
  main session's.
- `tool_response` is an object with `type` (`create` on a new file) and a `structuredPatch` array
  on Write as well as Edit.
- End to end, with `CLAUDE_PLUGIN_OPTION_TEST_GUARDS_ENABLED=true`: Writes of a zero-assertion
  Vitest file and a zero-assertion pytest file each returned `additionalContext` (504 characters
  for the first) naming `rule-zero-assertion` and carrying the rules note.

## Latency

Measured with `.work/tautological-tests/latency.sh`: 30 Edit payloads through
`exec-bash.mjs --require-true TEST_GUARDS_ENABLED test-scan.sh`, each paired with a `bash -c :`
spawn floor S in the same loop.

| Host | S (median) | test-scan p50 | test-scan p95 | p95 in S |
|---|---|---|---|---|
| WSL2, 2026-09-28 | 0.86 ms | 86 ms | 89 ms | 104 S |
| Windows fleet machine | not measured (needs approval to run over `/fleet:reach`) | | | |

Components on the same host, one run each of three: `node -e 0` 16-20 ms, the launcher running
`/bin/true` 23-31 ms, `cant-fail-scan.sh --file --lines` 34-45 ms, sourcing `hook-utils.sh`
3-4 ms, `jq` and `git check-ignore` 1-2 ms each.

The plan's budget of p95 at most 3 S does not hold on WSL. There a bash spawn costs under 1 ms, but
the node launcher that every exec-form hook needs costs 20 to 30 ms. The budget is open for a
decision; see the Phase 2 handoff.
