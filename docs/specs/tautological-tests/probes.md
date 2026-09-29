# Live probes: test-scan hook

Probes for Release 1 Phases 2 and 5. Each records the Claude Code version, how it was run, and
what it showed.

## `if` row matching and hook input (Claude Code 2.1.284, WSL2, 2026-09-28)

Run: `claude -p --model haiku --permission-mode acceptEdits --plugin-dir plugins/testing
--debug-file <log>` in a scratch git repository, with a project `settings.json` that appended each
PostToolUse payload, or a line per matching `if` row, to a file.

- A non-matching path starts nothing. A Write to `src/app.ts` logged "Skipping hook due to if
  condition ... not matching" for all 32 testing rows, and no test-scan process ran.
- Basename globs match at any depth: `Write(*.test.ts)` matched `src/deep/x.test.ts` and
  `src/deep/y.test.ts`, `Write(test_*.py)` matched `tests/test_more.py`, and `Write(*Tests.cs)`
  matched `src/MoreTests.cs`.
- Phase 3 repeat (Claude Code 2.1.284, 2026-09-28), same setup with the regenerated rows: a Write
  and then an Edit of `pkg/deep/sum_test.go` and of `tests/deep/Sum.Tests.ps1` each returned
  `additionalContext` naming `rule-zero-assertion` (`TestSum` at line 5, `adds` at line 2). The
  `_` in `*_test.go` and the capital `T` and extra dot in `*.Tests.ps1` match as written.
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

## Consumer settings hook environment (Claude Code 2.1.284, WSL2, 2026-09-29)

Question: does a hook declared in a project's `.claude/settings.json`, not in a plugin's
`hooks.json`, receive `CLAUDE_PLUGIN_ROOT` and `CLAUDE_PLUGIN_OPTION_*`?

Run: `env -u CLAUDE_PLUGIN_DATA claude -p --model haiku --permission-mode acceptEdits
--plugin-dir <probe plugin> --settings <file with pluginConfigs> --debug-file <log>` in a scratch
git repository. The probe plugin declared a boolean `userConfig` option and a PostToolUse
`Write|Edit` hook; the project settings declared a PostToolUse `Write|Edit` hook. Each hook
appended its `CLAUDE_PLUGIN*` and `CLAUDE_PROJECT*` variables to one file. The settings file set the
option through `pluginConfigs["probe5@inline"].options`.

- The consumer settings hook received only `CLAUDE_PROJECT_DIR`: no `CLAUDE_PLUGIN_ROOT`, no
  `CLAUDE_PLUGIN_DATA`, no `CLAUDE_PLUGIN_OPTION_*`.
- The plugin hook in the same session received `CLAUDE_PLUGIN_ROOT`, `CLAUDE_PLUGIN_DATA`,
  `CLAUDE_PROJECT_DIR` and `CLAUDE_PLUGIN_OPTION_PROBE_FLAG=true`.
- Without the `pluginConfigs` value, the option's `default: true` alone exported no
  `CLAUDE_PLUGIN_OPTION_PROBE_FLAG` to the plugin hook.
- The first run showed a `CLAUDE_PLUGIN_DATA` in the consumer hook. It was the calling shell's own
  (another plugin's data directory), inherited; the variable must be unset before the probe.

So the settings entry `/testing:setup check` prints passes `--enabled` to `test-scan.sh` and finds
the most recently installed `testing` plugin under `~/.claude/plugins/cache` itself.

Follow-up in the same repository and session setup, with the entry's shape in
`.claude/settings.json` (a shell-string command, one `Write(*.it.js)` and one `Edit(*.it.js)` row,
the lookup pointed at the branch's `test-scan.sh`, since the installed releases predate `--enabled`)
and `extend.js-vitest.files: ['*.it.js']` in `.claude/testing.yaml`:

- A Write to `notes3.txt` logged "Skipping hook due to if condition "Write(*.it.js)" not matching"
  and started nothing: a settings hook honors `if` the way a plugin hook does.
- A Write of a zero-assertion `src/sum.it.js` ran the command once and returned
  `additionalContext` naming `rule-zero-assertion` with the rules note, with no plugin option set.

## Latency

Measured with `.work/tautological-tests/latency.sh`: 30 Edit payloads through
`exec-bash.mjs --require-true TEST_GUARDS_ENABLED test-scan.sh`, each paired with a `bash -c :`
spawn floor S in the same loop.

| Host | S (median) | test-scan p50 | test-scan p95 | p95 in S |
|---|---|---|---|---|
| WSL2, 2026-09-28 | 0.86 ms | 86 ms | 89 ms | 104 S |
| Windows 11 Git Bash (`melo-desk-001`, via WSL interop), 2026-09-28 | 17.5 ms | 716 ms | 743 ms | 42 S |

Components on the same host, one run each of three: `node -e 0` 16-20 ms, the launcher running
`/bin/true` 23-31 ms, `cant-fail-scan.sh --file --lines` 34-45 ms, sourcing `hook-utils.sh`
3-4 ms, `jq` and `git check-ignore` 1-2 ms each.

Both p95 figures are within the Phase 2 budget: at most 150 ms on WSL and 1 s on Windows. That
budget replaced an earlier 3 S one (user decision, 2026-09-28). A budget in S cannot hold on WSL,
where a bash spawn costs under 1 ms but the node launcher that every exec-form hook needs costs 20
to 30 ms.

### Phase 5: `.claude/testing.yaml` (WSL2, 2026-09-29)

Same script, 50 samples per arm. "Before" is the branch head without Phase 5 (Phase 4b, more
rules than the Phase 2 row above), extracted with `git archive`. "With config" sets `HOME` to a
directory whose `.claude/testing.yaml` holds two excludes, one rule level and one `extend` list.

| Run | Load average | before p95 | no config p95 | with config p95 |
|---|---|---|---|---|
| idle, separate runs | under 8 | 116, 123 ms | 123, 126 ms | not measured |
| interleaved, 3 rounds | 22-27 | 189, 164, 177 ms | 175, 179, 179 ms | 181, 196, 188 ms |

With no layer file the scan does three file tests more and nothing else, and the loaded rounds put
it within noise of before (+2 ms on the round means). A layer file adds the resolver
(`resolve-config.sh --quick`, 9 ms alone) and the config parsing in the scanner: about +12 ms over
before on the round means. Idle before plus that delta is about 130-135 ms, inside the 150 ms
budget, but that figure is an estimate: the host stayed above load 20 for the whole session, and
every arm, before included, went over 150 ms under that load. Re-measure the config arm on an idle
host.

### Phase 6: `test-weaken` (WSL2, 2026-09-29)

Three arms per round, one sample of each per iteration, 50 samples: test-scan at the Phase 5 head
(`git archive`), test-scan with the Phase 6 scanner, and test-weaken on an Edit that drops one
`expect` line (the full path: inventory of both sides, context emitted). No config layer.

| Round | Load average | test-scan before p50/p95 | test-scan after p50/p95 | test-weaken p50/p95 |
|---|---|---|---|---|
| 1 | 33 | 213/253 ms | 213/237 ms | 172/196 ms |
| 2 | 34 | 215/251 ms | 215/239 ms | 178/194 ms |
| 3 | 36 | 215/272 ms | 214/259 ms | 179/219 ms |

The scanner change leaves test-scan within noise of before. test-weaken runs about 35 ms under
test-scan on every round, because `--inventory` skips the Playwright config walk and the rules. No
arm meets the 150 ms p95 budget at load 33-36, before included; the idle measurement moves to
Phase 8 with the Phase 5 config arm.
