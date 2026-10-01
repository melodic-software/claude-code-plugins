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
| idle, separate runs | under 8 | 116, 123 ms | 123, 126 ms | 130, 133, 131 ms (next section) |
| interleaved, 3 rounds | 22-27 | 189, 164, 177 ms | 175, 179, 179 ms | 181, 196, 188 ms |

With no layer file the scan does three file tests more and nothing else, and the loaded rounds put
it within noise of before (+2 ms on the round means). A layer file adds the resolver
(`resolve-config.sh --quick`, 9 ms alone) and the config parsing in the scanner: about +12 ms over
before on the round means. Idle before plus that delta is about 130-135 ms, inside the 150 ms
budget, but that figure is an estimate: the host stayed above load 20 for the whole session, and
every arm, before included, went over 150 ms under that load. Re-measure the config arm on an idle
host.

### Idle config arm (WSL2, 2026-09-29)

Three arms per round, one sample of each per iteration, 50 samples, each round started only at a
1-minute load below 8 (5.6-6.9 across the run), on the scanner that follows helpers to any depth:
test-scan with no layer file, test-scan with a user-layer `.claude/testing.yaml` (two excludes,
one rule level, one `extend` list), and test-weaken with the same layer on an Edit that removes a
test block. Each arm was first checked to emit its finding or weakening note.

| Round | test-scan no config p50/p95 | test-scan config p50/p95 | test-weaken config p50/p95 |
|---|---|---|---|
| 1 | 110/116 ms | 120/130 ms | 104/109 ms |
| 2 | 115/124 ms | 123/133 ms | 107/113 ms |
| 3 | 112/119 ms | 122/131 ms | 105/113 ms |

The layer file costs about 10 ms at p50 and 12-14 ms at p95, matching the loaded estimate above.
Every arm meets the 150 ms p95 budget at idle.

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

### Bash route: `test-scan-bash.sh` (WSL2, 2026-09-30)

Five arms per round, one sample of each per iteration, 50 samples, every arm through `node
exec-bash.mjs --require-true TEST_GUARDS_ENABLED`, started at a 1-minute load of 5.8-6.9. All
payloads are PostToolUse `Bash` payloads; the one-file arm carries a `bashEditDiff` naming one
created zero-assertion `*.test.ts` and emits its finding. "Direct" is the same file as a `Write`
payload through `test-scan.sh`, for the baseline.

| Round | option off (launcher only) | no diff, empty stdout | no diff, 300 KB stdout | one-file diff | direct test-scan |
|---|---|---|---|---|---|
| 1 | 20/23 ms | 27/31 ms | 59/66 ms | 114/129 ms | 106/114 ms |
| 2 | 20/22 ms | 27/31 ms | 58/65 ms | 113/119 ms | 104/114 ms |
| 3 | 20/22 ms | 27/30 ms | 61/66 ms | 113/119 ms | 105/111 ms |

Each cell is p50/p95. All arms meet the 150 ms p95 budget. The one-file route costs about 9 ms
over a direct Write scan (one extra `jq`, the child shell and its `hook-utils.sh` source). A
payload without `bashEditDiff` exits after reading stdin and one substring test. The 300 KB arm
pays for reading and validating the payload in `hook::buffer_stdin_to`. The option-off arm is what
every Bash call costs a user who has not turned `test_guards_enabled` on, since a `Bash` row has no
glob to keep the launcher from starting: one `node` start per Bash call. The route was not
measured above load 7; the direct arm alone reads 134-140 ms p95 at load 11-12, so the one-file
margin is an idle-host figure.

Budget figures, same host at a load of about 5.3. S is `bash -c :`; the four arms ran interleaved,
50 samples, each one-file fire with its own `tool_use_id` (the per-call marker skips a repeated id).
p50/p95: S 1.0/1.2 ms; option off 21.8/25.4 ms (22 S); no diff 30.1/33.7 ms (30 S); one-file diff
115.5/127.6 ms (115 S). `scripts/hook-census.sh` spawns, process creations plus execs, three runs
each with identical results: option off 1 (0 creations, 1 exec), no diff 3 (1 creation, 2 execs),
one-file diff 96 (59 creations, 37 execs). The first two are the
ceilings in `.performance/ratchets.json`. A mutant that runs `jq` before the script's substring
test raised the no-diff count from 3 to 5, and `ratchet.py check` reported it above its ceiling.
Versions: `bash=5.3.9(1)-release sh=/usr/bin/dash git 2.53.0 jq-1.8.2 strace 6.19`; strace came
from an extracted `.deb`, not an installed package. The CI runner's versions differ, so its ratchet
step is the confirmation.

## Release 2 probes

Claude Code 2.1.285, WSL2, 2026-09-30. Each probe ran in its own scratch git repository under
`.work/tautological-tests-judge/probe/` with throwaway project-scope hooks; logs, hook payloads and
tmux pane captures are in its `logs/` folder. Sessions started through a wrapper that unsets the
calling session's `CLAUDE_*` variables. Interactive probes ran `claude` in tmux. "stand-in judge"
is the Phase 3 judge command with `timeout 150`, `TEST_JUDGE_ACTIVE=1`, `--system-prompt`,
`--tools Read,Grep,Glob`, `--allowedTools "Read(<repo>/**)" "Grep(<repo>/**)" "Glob(<repo>/**)"`,
`--settings '{"disableAllHooks":true}'`, `--setting-sources ""`, `--strict-mcp-config`,
`--effort medium` and `--max-budget-usd`.

| id | version | command | observed | verdict | design thread |
|---|---|---|---|---|---|
| R2-P1 | 2.1.285 | `claude -p` (haiku, sonnet, opus) spawning a general-purpose subagent that runs Bash; PreToolUse and SubagentStart hooks log payloads | the subagent's Bash PreToolUse carries `agent_id` and the parent's `session_id` in all three sessions; `CLAUDE_CODE_SESSION_ID` in the hook env matches | holds | DT8 |
| R2-P2 | 2.1.285 | same sessions; `jq '.message.model'` on assistant lines | main transcript lines: `claude-haiku-4-5-20251001`, `claude-sonnet-5`, `claude-opus-5-5`; later sonnet runs the same day: `claude-sonnet-5-5` (both contain the class); subagent lines go to `<session>/subagents/agent-*.jsonl`, never the main transcript; a subagent's hook payloads (PreToolUse, SubagentStart) carry `agent_id` and the main `transcript_path` and `session_id`, and its file is `<dirname(transcript_path)>/<session_id>/subagents/agent-<agent_id>.jsonl` (4 subagent sessions, `p12-hooks.jsonl`). untested: a `<synthetic>` line on 2.1.285 (none produced); 52 seen in this machine's 2.1.283-2.1.284 transcripts, from usage-limit errors (`isApiErrorMessage: true`) and one "No response requested." | holds | DT3 |
| R2-P3 | 2.1.285 | the Phase 3 judge command exactly as `docs/specs/tautological-tests-judge/plan.md` states it (stand-in flags plus `--disable-slash-commands`, parent environment unchanged, `ANTHROPIC_API_KEY` unset), model `haiku`, started from a Stop hook of a `claude -p` haiku session; variants: a six-question prompt at `--max-budget-usd 0.50`, and `--max-budget-usd 0.0001`; `--output-format stream-json --verbose --include-hook-events` added for observation | re-ran 2026-09-30 after the DT16 amendment. init: `skills: []`, `slash_commands: []`, `mcp_servers: []`, plugins only 2 builtin, tools Glob Grep Read; 0 hook events. No CLAUDE.md: codeword "NONE", no `ZEBRA` in the stream. System prompt replaced: reply starts "SYSPROMPT-OK", first turn 3,302 input tokens against 35,040 for the first run's default child; asked whether its system prompt mentions Claude Code, the model said YES, citing a system reminder. Model: `claude-haiku-4-5-20251001`. Budget: `error_max_budget_usd` after 1 turn, rc 1, $0.0042 spent against $0.0001 (one turn overshoots). Scoped allow rules refused the outside Read and Grep (`permission_denied`, "Path is outside allowed working directories"); the inside Read succeeded. `apiKeySource: "none"` with no key set; the run succeeded on the claude.ai login. Key billing is settled by the docs, not probed: "In non-interactive mode (`-p`), the key is always used when present" (code.claude.com/docs/en/env-vars, fetched 2026-09-30); the first run's placeholder key gave `apiKeySource: "ANTHROPIC_API_KEY"`. Hook env has `CLAUDE_CODE_CHILD_SESSION=1`. Logs `p3r-*` | holds | DT16 |
| R2-P4 | 2.1.285 | two interactive haiku sessions in tmux; PostToolUse `async: true` Bash hook that starts a `claude -p` grandchild alive 90 s and logs a heartbeat; one session then ran `/clear`, the other `/exit` | the hook and grandchild kept running after the turn ended and while the session answered a new prompt; both survived `/clear` and interactive exit (after exit, 2 orphaned processes: hook shell and grandchild), received no signal, and finished normally ("grandchild exit=0", result "done", "hook end"); none remained afterward. Windows variant (native `claude.exe` 2.1.285 on melo-desk-001, hooks under Git Bash 5.3.15, one interactive haiku session driven over WSL interop; the turn, then a new prompt, `/clear`, `/exit`): the same result. The hook heartbeat continued through the new prompt, `/clear` and exit (exit rc=0); after exit 5 orphaned processes remained (four `bash.exe`: the `bash -c` wrapper, the hook script and two subshells; plus the `claude.exe` grandchild), none received a signal, and they finished normally ("grandchild exit=0", result "done", "hook end"); none remained afterward | holds | DT16 |
| R2-P5 | 2.1.285 | interactive haiku session in tmux, Stop hook returning `systemMessage` with and without `decision: block` | pane shows "Stop says: SYSMSG-BLOCK-A" and "Stop says: SYSMSG-ALLOW-A"; the block reason is shown to the user as "Stop hook error: Reply with exactly the token FORCED-A ..." | holds | DT16 |
| R2-P6 | 2.1.285 | `claude -p` haiku, Stop hook blocks when `stop_hook_active` is false | first Stop `stop_hook_active: false`, block, forced turn replied "FORCED-A"; second Stop `stop_hook_active: true`, allowed | holds | DT2 |
| R2-P7 | 2.1.285 | stand-in judge, opus at medium effort, one test file with 1 test and one with 10, 3 runs each | 1 test: 11.1-12.1 s (process wall 13.1 s), 3 turns, output 1026-1071 tokens, input about 7.5k (cache write plus read), $0.023-0.054. 10 tests: 27.5-31.0 s (wall 29.0 s), 4-5 turns, output 3118-3561 tokens, input 13-18k, $0.073-0.090. n=3, so the ten-test figure is a maximum, not a p95 | holds | DT16 |
| R2-P8 | 2.1.285 | interactive haiku session in tmux with `/clear`; then `claude -p --resume <id>` and `claude -p --resume <id> --fork-session` | `/clear`: new `session_id` and transcript (SessionEnd reason "clear", SessionStart source "clear"); `--resume`: same `session_id` (source "resume"); fork: new `session_id` and transcript (source "fork"), and its SessionStart payload names no parent session. Resume and fork were run through `-p` only. /compact (re-run 2026-09-30): same session_id, same transcript_path, SessionStart source "compact" | fails | DT8 |
| R2-P9 | 2.1.285 | a Stop hook logs `CLAUDE_CODE_SESSION_ATTENDED`, `CLAUDE_CODE_ENTRYPOINT` and `permission_mode`, haiku, with (b) and (d) re-run on sonnet because haiku did not enter auto mode: (a) interactive default and (b) interactive `--permission-mode auto`, both in tmux; (c) `claude -p`; (d) `claude -p --permission-mode auto`; (e) `claude --bg`. Pass rule fixed before running: (a) and (b) read exactly `1`; (c), (d) and (e) anything else or absent | re-ran 2026-09-30 after the DT15 amendment. ATTENDED / ENTRYPOINT / permission_mode: (a) `1` / `cli` / `default`; (b) `1` / `cli` / `default` (haiku shows "manual mode on"); (c) `0` / `sdk-cli` / `default`; (d) `0` / `sdk-cli` / `default`; (e) `0` / `cli` / `default`. SessionStart and UserPromptSubmit carry the same values. The Stop block forced a turn in all five. Haiku did not engage auto in (b) or (d), so both re-ran on sonnet: (b) `1` / `cli` / `auto` (pane "auto mode on"), (d) `0` / `sdk-cli` / `auto`. From the first run: in `-p` the forced turn's reply replaces the `-p` result; `systemMessage` goes to stream-json as `system`/`informational` and to the transcript as `hook_system_message`, not to text or json output. Logs `p9r-hooks.jsonl` (c, d), `p5r-hooks.jsonl` (a, b, e), `p5r-pane-a.txt`, `p5r-pane-b.txt`, `p5r-pane-b-sonnet.txt`, `p5r-bg-logs.txt` | holds | DT15 |
| R2-P10 | 2.1.285 | `claude -p` haiku with two Stop hooks that each block once | both reasons arrive as two separate "Stop hook feedback" user messages in one Stop; one forced turn, which obeyed only one ("FORCED-B"); the next Stop has `stop_hook_active: true` for both and both allow | holds | DT16 |
| R2-P11 | 2.1.285 | `claude -p` with the installed `testing` 0.11.5 plugin hook (option set through `pluginConfigs`) writing `src/sum.test.js`; separately the `setup check` consumer entry (`test-scan.sh --enabled` from the plugin cache, `*.it.js` through `.claude/testing.yaml`) writing `src/sum2.it.js` | both runs wrote `marks/call-<tool_use_id>` under `~/.claude/plugins/data/testing-melodic-software/`; the plugin hook through `CLAUDE_PLUGIN_DATA`, the consumer entry by deriving it from the cache path; both returned `rule-zero-assertion` | holds | DT8 |
| R2-P12 | 2.1.285 | `--plugin-dir` variant only. Interactive `claude --plugin-dir <worktree>/plugins/testing --settings r2logs/p12-settings.json --setting-sources project,local --model sonnet --permission-mode auto` in tmux (ATTENDED=1). The settings file sets `pluginConfigs["testing@inline"]` (`test_guards_enabled`, `test_judge_enabled` true) and adds timestamp logger hooks. Scratch repo `probe/p12` (vitest); external CLAUDE.md imports declined. Judge defaults; `TEST_JUDGE_CMD` is a pass-through wrapper that logs cost. Turn 1 writes `expect(add(a, b)).toBe(a + b)` verbatim, then waits 60 s (`node -e "setTimeout(() => {}, 60000)"`, declared before the run), then runs vitest. Turn 2 is unrelated ("reply OK"). Turn 3 appends `expect(add(2, 3)).toBe(5)` with the same wait. For a blocking Stop, Stop wait = `stop_hook_summary` timestamp minus the logger Stop hook's start. Installed-copy variant deferred: it needs a user-scope marketplace or install | Turn 1: a background run (22:51:08-22:51:16, `claude-opus-5-5`, 7.7 s, $0.0486) wrote a FLAG verdict (judged_at 22:51:16Z) 40.6 s before the Stop. This held only because of the declared 60 s wait: the Stop came 68.5 s after the write. In R2-P13's natural turns the Stop came 8-11 s after the write, inside the 20 s debounce. That Stop blocked once ("The test judge reviewed 1 test (1 FLAG, 0 PASS, 0 UNKNOWN). Findings: .../p12/.work/reviews/main/20260930T225157Z-test-judge.md ..."). The forced turn quoted the verdict and diff, applied nothing and asked the user. The same counts arrived as a `hook_system_message`, shown in the pane as "Stop says: test judge: reviewed 1 test (1 FLAG, 0 PASS, 0 UNKNOWN) ...". Hook wait 145 ms; the following `stop_hook_active` Stop did not block (41 ms). Turn 2 left the forced turn's question unanswered: no block, nothing re-relayed (124 ms). Turn 3: PASS (judged 22:54:05Z, 4.7 s, $0.0130) and one forced turn, "1 test (0 FLAG, 1 PASS, 0 UNKNOWN)", so the FLAG was not relayed again; the next `stop_hook_active` Stop took 44 ms and did not block. 2 runs, 2 `runs/` files, $0.0616. The writer saw test-scan's `rule-recomputed-derived` note and kept the test as instructed. Installed copy not run: an install from this branch writes `~/.claude/plugins/known_marketplaces.json` (a marketplace for the branch) and `~/.claude/plugins/installed_plugins.json` (where `-s project` installs are also recorded, with `projectPath`). The only marketplace that carries `testing`, melodic-software, is GitHub main at 0.11.9, which has no judge. Logs `r2logs/p12-*` | fails | DT2, DT15, DT16 |
| R2-P13 | 2.1.286 | Same session setup as R2-P12 (`--plugin-dir`, `--settings r2logs/p13r2-settings.json --setting-sources project,local`, sonnet, auto, tmux, wrapper) in a fresh `probe/p13`. 5 scripted user turns, each asking for 3 tests plus the code, test-first: turns 1-3 in `src/money.test.js`, turns 4-5 in `src/slug.test.js`. Natural timing. Each prompt ends "Make every file change with the Write or Edit tool, never with shell commands; use Bash only to run the tests." (added before run 2). Bars, fixed before running: forced turns at most 1 per task end and 0 at each `stop_hook_active` Stop; superseded or discarded runs (no verdict ever relayed, or no usable result) at most a third of runs; longest judge Stop wait under 60 s | Run 1 (without that sentence) is not scored. Dropping user settings also dropped the guardrails shell-write guard, and the writer wrote 12 of 15 tests with `cat >> ... <<EOF` and `sed -i`. Nothing recorded those writes, so 1 run judged 3 tests, and turns 2-5 ended with no judge message. Run 1 also met all three bars (1 forced turn, 0 of 1 runs superseded, max Stop wait 16.9 s); it was rerun because only 3 of 15 tests reached the judge. Run 2: all 15 tests went through Write and Edit (0 Bash writes to a test file). 9 background jobs started; 4 exited at the debounce because the file changed. 5 judge runs (5 `runs/` files), all started by background jobs; 0 superseded or discarded, 0 partial. 15 verdicts (14 PASS, 1 FLAG), all `claude-opus-5-5` at medium, all relayed. Forced turns: exactly 1 at each of the 5 task ends, 0 at the 5 `stop_hook_active` Stops. Blocking Stop waits: 20.0, 28.2, 18.1, 19.6 and 21.6 s (max 28.2 s); non-blocking Stops took 45-59 ms. Each Stop came 7.9-11.4 s after the turn's last test write, inside the 20 s debounce, so no verdict was ready at any Stop, and each Stop waited for the background job. Cost per run $0.0296-$0.0607 (7.6-19.3 s wall), $0.2062 in total. Logs `r2logs/p13r2-*`; run 1 `r2logs/p13-*` and `probe/p13.run1` | holds | DT16 |
| R2-P14 | 2.1.286 | native Windows (melo-desk-001), testing at 0643e9188, Git Bash 5.3.15, node v24.21.0, jq.exe 1.8.2: `node exec-bash.mjs --require-true TEST_GUARDS_ENABLED --require-true TEST_JUDGE_ENABLED test-judge.sh` timed in-process with real backslash payloads; idle Stop (no records) x20; Stop with 5 in-doubt tests in one file whose verdicts came from test-scan.sh plus test-judge-bg.sh with a stub TEST_JUDGE_CMD, x10 warm and x10 cold (derive/ cleared), relayed/ reset between runs; e2e: interactive claude.exe haiku with --plugin-dir and --settings pluginConfigs, one Write plus sleep 30 | idle p50 191 ms, p95 215 ms. Warm ready p50 794 ms, p95 1644 ms, 5/5 relayed, 1 FLAG kept as FLAG. Cold p50 1474 ms, p95 1609 ms. Five files warm p50 1155 ms (first run cold, 4481 ms). No process left behind. e2e: the opus judge returned FLAG with diff `toBe(5)`, but validate then made it UNKNOWN because one quoted line (`return a + b;`) came from src/add.js, not the test file. Fixed in 2e9a12431 (a quote may come from any file in the repository); re-checked on Linux with a real opus judge at medium: FLAG quoting the implementation line relayed as "1 FLAG" attended and unattended, findings row written, $0.015-0.017 per run | holds | DT16 |
| R2-P15 | 2.1.286 | `claude -p --model haiku --tools Read,Grep,Glob --allowedTools "Read(<repo>/**)" "Grep(<repo>/**)" "Glob(<repo>/**)" --disable-slash-commands --settings '{"disableAllHooks":true}' --setting-sources "" --strict-mcp-config --output-format stream-json --verbose` from cwd=repo, repo containing `link.txt` -> `../outside/canary.txt` and `linkdir` -> `../outside` | (a) Read link.txt: permission denied, "resolves through a symlink" to outside; (b) Read linkdir/canary.txt: same denial; (c) Grep CANARY: "No matches found" (symlinked dir not traversed); (d) control Read of outside path: permission denied; CANARY-7f3a91 absent from all tool_results and final text | holds | DT16 |

## `bashEditDiff` (Claude Code 2.1.285, WSL2, 2026-09-30)

Question: does a PostToolUse `Bash` hook receive the files a Bash call changed, and in which modes?

Run: `claude -p --model haiku --permission-mode <mode> --setting-sources project --allowedTools Bash
--debug-file <log>` in a scratch git repository with one committed test file (`src/sum.test.ts`),
one committed source file and a project `.claude/settings.json` whose PostToolUse `Bash` hook
appended the whole hook input to a file. Three prompts, each told to use only Bash: (a) `sed -i` on
the tracked test file, (b) `cat` with a heredoc writing the untracked `src/new.test.ts`, (c) `sed -i`
on the tracked `README.md`. `bashEditDiffEnabled` was set through `--settings '<json>'` where a row
says so. Auto mode ran on sonnet, because haiku does not engage it (the payload then reads
`permission_mode: "default"`). The repository was reset between runs.

- The field is `tool_response.bashEditDiff`, beside `stdout`, `stderr`, `interrupted`, `isImage` and
  `noOutputExpected`. It is absent, not empty, when the call is not recorded.
- Modes, for each of (a), (b) and (c) unless stated:

  | Mode and setting | `bashEditDiff` |
  |---|---|
  | `default`, no setting | absent |
  | `acceptEdits`, no setting | absent |
  | `auto` (sonnet), no setting | absent (`-p`, and (a) interactive in tmux) |
  | `bypassPermissions`, no setting | absent |
  | `acceptEdits`, `bashEditDiffEnabled: true` in `--settings` | present |
  | `auto` (sonnet), `bashEditDiffEnabled: true` in `--settings`, (a) only | present |
  | `default`, `CLAUDE_CODE_BASH_EDIT_DIFF=1`, (a) only | present |
  | `acceptEdits` or `auto`, `bashEditDiffEnabled: false`, (a) only | absent (also absent without the key, so this does not show `false` switching recording off) |
  | `acceptEdits`, `bashEditDiffEnabled: true` in the project `.claude/settings.json`, (a) only | absent |

  The docs (code.claude.com/docs/en/hooks#bash and settings-reference#basheditdiffenabled, fetched
  2026-09-30) say auto and `bypassPermissions` record "only when Claude Code directs Claude to edit
  files through Bash"; with a prompt that named `sed -i` and `cat >` neither recorded anything here.
  The docs say a `true` counts only from user settings, `--settings` or managed settings. The runs
  confirm the `--settings` positive and the project-file negative; user and managed scope were not
  run (every run used `--setting-sources project`). Per the docs, the hook sees the field only for
  a consumer who set the key at user or managed scope, or the environment variable.
- Shape, from the `acceptEdits` + `true` runs: `{"files": [...], "moreFiles": 0, "changedFiles":
  [...]}`. `changedFiles` holds absolute paths. `files` holds `{"filePath": <absolute>, "hunks":
  [{"oldStart", "oldLines", "newStart", "newLines", "lines": ["-old", "+new", " context"]}]}` per
  file, plus `"created": true` on a new file. There is no separate patch string and no line-range
  field. `unavailable`, `skipped` and `shared` never appeared.
- An untracked new file appears. (b) listed `src/new.test.ts` with `created: true` and one hunk
  (`oldStart: 0`, `newStart: 1`, every line prefixed `+`).
- Limits: one call writing eight files (seven new `src/gen<N>.test.ts` and an edited `README.md`)
  returned `changedFiles` with all eight, `files` with the first five (each with its hunks) and
  `moreFiles: 3`. A routing hook therefore reads `changedFiles`, not `files`. A file the repository's
  `.gitignore` ignores (`src/ignored.log`, written in the same call) was not listed.
- A PostToolUse `if` row cannot filter on the changed files. It matches the command string: with
  `bashEditDiffEnabled: true`, `Bash(*)` fired on both (a) and (b), `Bash(sed *)` fired only on (a),
  `Bash(cat *)` only on (b), and `Bash(*.test.ts*)` fired on (a), whose command names
  `src/sum.test.ts`, but was skipped for (b) ("Skipping hook due to if condition"), whose command
  also contains `.test.ts` (`cat > src/new.test.ts << 'EOF'` and a multi-line body). A command
  string that names the test file can still fail to match, so a command-string row cannot stand in
  for the changed-file list. A row that must see every Bash call that
  changed a test file has to be `Bash(*)` and start a process for every Bash call, and decide from
  `changedFiles`.
- End to end through the plugin: `claude -p --model haiku --permission-mode acceptEdits
  --setting-sources project --plugin-dir plugins/testing --settings <file>`, the file holding
  `bashEditDiffEnabled: true` and `pluginConfigs["testing@inline"].options.test_guards_enabled:
  true`, told to write a vitest test without an assertion through one `cat` heredoc. The
  `PostToolUse:Bash` hook ("Scanning test files the command changed...") returned
  `additionalContext` naming `rule-zero-assertion` at `src/calc.test.ts:5`, and the agent's reply
  reported the zero-assertion finding.
- Not probed: Windows Git Bash (the shape, path separators and mode behavior there need the owner
  or a fleet run); `bashEditDiffEnabled` at user or managed scope; `false` against a `true` from a
  higher-precedence source; `PowerShell`, which the docs say has the same fields; a subagent's Bash call
  (the `shared` flag); `moreFiles` beyond the 200-path cap; the `CLAUDE_CODE_BASH_EDIT_DIFF=0` case.
