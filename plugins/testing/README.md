# testing

A Claude Code plugin for the **test stage** of a disciplined dev workflow. Plan
what needs testing, author tests at the right level, verify the running app
end-to-end, diagnose failures to root cause, and catch tests that cannot fail. Eight
skills, one concern: proving behavior with tests.

| Skill | What it does |
|---|---|
| `/testing:plan` | Coverage-gap analysis. Classify changed files by required test type, identify gaps, prioritize by regression risk. |
| `/testing:write` | Test authoring discipline. Vertical-slice TDD, test-type selection, naming, placement, fixture patterns, four-pillars assessment. |
| `/testing:run-e2e` | Live app verification. Start the app via the project's orchestrator, drive UI/API flows with token-efficient browser automation, capture evidence; includes a non-UI smoke-test playbook (MCP stdio handshake, shell/PowerShell surfaces). |
| `/testing:diagnose` | Failing-test diagnosis. Failure classification, root-cause analysis (never retry blindly), then the reproduce → isolate → fix → retest → regression loop. |
| `/testing:audit` | Can't-fail test detection: a deterministic script runs twelve rules across JS/TS, Python, C#, Bash, PowerShell and Go, from assertion-free bodies and self-identical (recomputed-expectation) assertions to unawaited assertions, conditional assertions and Playwright retry or `test.only` configs. `--check` fails on the first two (Bash-harness findings only with `--strict`); `--strict` adds mock-only oracles and the two Playwright config rules; the other seven only report. It reports with a coverage denominator and opt-in persists findings for a review fix pass. |
| `/testing:setup` | Configure the can't-fail checks: `check` prints the resolved `.claude/testing.yaml`, the test-lint rules missing per language, an optional instruction line to paste, and a settings hook entry for test globs the shipped hook skips; `apply` writes `.claude/testing.yaml`. |
| `/testing:check` | Read-only and model-invocable. Reports whether `jq` resolves for the plugin's hooks, with the install route from `prerequisites.json` when it does not. It never installs. |
| `testing:test-value` | Model-invoked guidance, loaded by the review and implementation agents and the `test-scan` hook: where each expected value must come from, when call-count and database checks are legitimate, and the can't-fail taxonomy keyed to `/testing:audit` rule ids. |

## Works in any repo

- **Reads your conventions, assumes none.** Test frameworks, project locations,
  naming, fixture patterns, and the e2e-orchestrator configuration come from your own
  project's `CLAUDE.md` / rules and existing test projects; the skills infer from what
  exists when nothing is documented.
- **Cross-plugin refs degrade gracefully.** Test invocation defers to the `toolchain`
  plugin's `/toolchain:check` when installed and to the project's own test command
  otherwise; TDD design questions route to `/tdd:principles`, browser mechanics to
  `/playwright:playwright`, outcome sign-off to `/verification:confirm`, and the
  implement loop to `/implementation:implement`. Each is used when installed and
  substituted with inline guidance or a manual handoff when absent. No step blocks on a
  missing plugin.
- **Self-contained.** Test-type tables, the E2E evidence contract, the non-UI
  smoke-test playbook, and diagnosis loops ship inside the plugin and are referenced
  via `${CLAUDE_PLUGIN_ROOT}`.

## Requirements

- **Node.js** on `PATH`. Every hook row launches through `node hooks/exec-bash.mjs`, which
  finds Bash. A missing `node` is a hook launch error, not a skip notice.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install testing@melodic-software
```

## Configuration

Test structure and conventions come from your own project's `CLAUDE.md` and rules.

`userConfig` options, prompted by Claude Code at enable time (all listed under Options reference
below):

- `test_guards_enabled` (default `false`) turns on two hooks. `test-scan` (PostToolUse) runs the
  can't-fail scanner on each test file Claude writes or edits and returns the findings as
  context. `test-weaken` (PreToolUse) asks Claude for a reason when an edit removes or skips tests
  or assertions.
- `test_judge_enabled` (default `false`, and only effective with `test_guards_enabled`, whose scan
  records the tests it judges) turns on the task-end test judge, described below.
  `test_judge_model` (default `opus`) and `test_judge_fallback_model` (default `sonnet`) name the
  judge's model class, and `test_judge_effort` (default `medium`) its effort.
  `test_judge_session_runs` (unset: no limit) caps the judge runs one session starts.
- `stdin_read_timeout` (default `2` seconds) bounds how long a hook waits on its input before it
  fails open.

### Task-end test judge

A separate headless `claude -p` run asks one question of each test block the session created or
changed: where did its expected value come from? It answers FLAG (the value restates the
implementation), PASS or UNKNOWN, quotes its evidence, and proposes a diff for a FLAG. It never
applies anything. A background job judges soon after a write; at the end of the task the Stop hook
waits for any run still going, judges what is left (10 tests per task end, the rest at the next
one), writes a review-findings file (under `.work/reviews/<branch>/`, or the `memory_dir` that
`.claude/topic-docs.yaml` names), and shows the counts. In an interactive session it also asks
Claude once to show you each verdict and proposed diff and wait; unattended sessions get the
counts and the file only. A session that ended before its verdicts were shown gets them named at
the next session start. The writing agent never supplies the judge's prompt, model or output, and
the judge's model class always differs from every model that wrote the tests: when the configured
class wrote them, the fallback or the next of `opus`, `sonnet`, `haiku` is used, and when all
three wrote them the tests are reported UNKNOWN.

Before a verdict is shown, each quote must appear verbatim, whitespace trimmed, in the test file or
in another file of the repository (tracked, or untracked and not ignored), since the line of code
an expected value restates is often the best evidence; a quote found nowhere, or a FLAG whose
diff does not apply or touches another file, is shown as UNKNOWN with only that reason, never its
evidence, source or diff. The repository is the git toplevel of the test file's own directory,
whatever the hook's working directory. In the findings file each judge field is kept on one line
and cut at 500 characters, at most 20 quotes are shown, a diff is cut at 20,000 characters, and
the diff's fence is longer than any run of backticks inside it, so judge text cannot add a heading,
a table row or a fence. The memory root and the findings directory must resolve, symbolic links
followed, inside the checkout, before and after they are created. The `.gitignore` is written only
where no name exists yet, or kept when it is a regular file; a link, FIFO or anything else there is
refused. The findings file is written to a new temporary file in the checked directory, the
directory is checked again, and the file then takes the first free name with `mv -n`, so any name
already taken (by a file, a link or anything else) is skipped. A check that fails sends the file
to `findings/` in the plugin data directory. A local process that swaps a directory between those
steps can still race them; that residual is accepted. A
`memory_dir` with characters outside `[A-Za-z0-9._/-]` or a `..` component is ignored for `.work`.

What you can tune: both hooks on or off, the judge's model classes and effort, the per-session run
limit, the test-file globs, adapters and rule levels in `.claude/testing.yaml`, and a per-test
`cant-fail-ok: <reason>` marker. What is fixed: the judge's one question; its one forced turn
relays verdicts for you to approve, and it never gates a stop, a commit or `--check` and never
blocks on its own failure; it never applies a fix; and its malfunction guards (a
$0.90 budget per started ten tests in one run, a 150 s hang bound, three judge runs at once per
machine).

What it reaches: only test blocks the session created or changed, or that gained a
`cant-fail-ok:` marker. It judges the block's text, so a stub set up in `beforeEach` or a snapshot
kept in a `.snap` file is outside what it sees. A bash test script with no test blocks is judged
as one whole file, with the changed lines as a hint. A test file a Bash call changed is recorded
and judged when Claude Code records the call's changed files (`bashEditDiffEnabled: true` in
user, `--settings` or managed settings, or `CLAUDE_CODE_BASH_EDIT_DIFF=1`, and within the Bash
route's limits below); no background job starts for a Bash call, so the Stop hook judges those
tests itself. Test files written through an MCP tool are not recorded, so they are not judged. A
test file in no git repository is not judged: the judge's reads are scoped to the repository, so
it is reported UNKNOWN, "no repository". A symbolic link inside the repository that points outside
it does not widen the judge's reach: its scoped Read is checked against the link's resolved target
and refused, and its Grep does not follow a linked directory (probe R2-P15). A
glob added only through the consumer settings entry `/testing:setup check` prints
(`test-scan.sh --enabled`) is recorded in the same state, so with both options on the Stop hook
judges those tests at the task end, again with no background job ahead of it.

`/testing:run-e2e` reads one optional consumer-project config surface,
`.claude/testing/e2e.md`: `recording` (`video | gif | off`, default `off`) and
`browser_mode` (`headed | headless`, default `headless`). Both defaults preserve current
behavior, so the file is optional. Its keys, defaults, and precedence are documented in
the skill's bundled `run-e2e/context/e2e-config.md`; it layers per the marketplace
config-cascade convention.

`/testing:audit` and the `test-scan` hook read `.claude/testing.yaml` through the same cascade
(`~/.claude/testing.yaml`, the team file, `.claude/testing.local.yaml`): adapters to turn off or
allow, path globs to exclude or include, extra adapter globs, consumer adapters, and a level per
rule (`off`, `warn`, `error`). `/testing:setup` documents the keys and writes the file.

### Test files written through Bash

`test-scan` also scans test files a Bash call changed (`cat > foo.test.ts`, `sed -i`, a generator
script), when `test_guards_enabled` is on and Claude Code records the call's changed files. It reads
`tool_response.bashEditDiff`, a best-effort beta field that Claude Code adds to the `PostToolUse`
payload of a Bash call:

- **Precondition.** Set `bashEditDiffEnabled: true` in your user settings, in `--settings`, or in
  managed settings (a project `.claude/settings.json` value is ignored), or set the environment
  variable `CLAUDE_CODE_BASH_EDIT_DIFF=1`. Without one of these the field was absent in every mode
  probed (`default`, `acceptEdits`, `auto` and `bypassPermissions`), and the hook finds nothing to
  scan. The probe rows are in
  [probes.md](../../docs/specs/tautological-tests/probes.md#basheditdiff-claude-code-21285-wsl2-2026-09-30).
- **Scope.** A created test file reports every test block. A modified file reports only the blocks
  its hunks touch, the same as an Edit. A file the repository ignores is skipped.
- **Limits.** The payload carries hunks for the first five changed files only, so a modified test
  file past the fifth is not scanned, and one call scans at most four test files. The shipped
  adapters' globs decide what counts as a test file; a glob added through `.claude/testing.yaml` is
  not covered on this path. `test-weaken` (PreToolUse) sees Write and Edit only: a Bash call that
  removes assertions is not flagged. Windows Git Bash is not probed.
- **Cost.** A Bash hook row cannot filter on the changed files, so the row has no `if` and Claude
  Code starts its node launcher for every Bash call, whatever `test_guards_enabled` says. The
  [hook budget](../../docs/conventions/hook-budget/README.md) is k × S, where S is one `bash -c :`
  spawn and k the processes one fire starts. On WSL2, S was 1.0 ms (p50 of 50 samples interleaved
  with the hook arms, at a load of about 5; Windows is not measured):
  - Option off, the default: k = 1 (node; the option gate closes before bash starts), 22 ms, about
    22 S.
  - Option on, no recorded change, which is every Bash call for an opted-in user: k = 2 (node, then
    bash), 30 ms, about 30 S.
  - Option on, a call that changed one test file: the scan itself, 96 process creations and execs,
    116 ms, about 115 S. It runs only for such a call, so it is not always-on.

  The multiples read high because S is small on Linux: starting node costs about 22 ms against 1 ms
  for bash. `.performance/ratchets.json` holds the first two paths as spawn-count ceilings
  (`testing-posttooluse-bash-test-scan-option-off-spawns`, 1, and
  `testing-posttooluse-bash-test-scan-no-diff-spawns`, 3). A ceiling counts process creations plus
  execs, so the two-process path counts 3.

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `test_guards_enabled` | boolean | `false` | `CLAUDE_PLUGIN_OPTION_TEST_GUARDS_ENABLED` | Scan each test file Claude writes or edits for tests that cannot fail, and ask Claude for a reason when an edit removes or skips tests or assertions. Off by default. |
| `test_judge_enabled` | boolean | `false` | `CLAUDE_PLUGIN_OPTION_TEST_JUDGE_ENABLED` | At the end of each task, a separate model asks where the expected value of each test the session created or changed came from, and reports FLAG, PASS or UNKNOWN with quoted evidence and a proposed fix it never applies. Needs test_guards_enabled, whose scan records the tests it judges. Off by default. |
| `test_judge_model` | string | `"opus"` | `CLAUDE_PLUGIN_OPTION_TEST_JUDGE_MODEL` | Model class the judge runs on: fable, opus, sonnet or haiku. When a model of that class wrote the tests, the fallback or another class is used. |
| `test_judge_fallback_model` | string | `"sonnet"` | `CLAUDE_PLUGIN_OPTION_TEST_JUDGE_FALLBACK_MODEL` | Model class the judge uses when the main class wrote the tests: fable, opus, sonnet or haiku. |
| `test_judge_effort` | string | `"medium"` | `CLAUDE_PLUGIN_OPTION_TEST_JUDGE_EFFORT` | Effort level for the judge: low, medium, high, xhigh or max. |
| `test_judge_session_runs` | number<br>*min 1* | *(none)* | `CLAUDE_PLUGIN_OPTION_TEST_JUDGE_SESSION_RUNS` | Most judge runs one session may start (one run judges one file). Unset means no limit. |
| `stdin_read_timeout` | number<br>*min 1* | `2` | `CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT` | Idle bound on reading the hook payload from stdin: how long the pipe may go silent before the hook gives up and fails open |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively.** Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure testing@<marketplace>`.
2. **Headless.** Repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install testing@<marketplace> -s <scope> --config test_guards_enabled=<value>
   ```

   The same command reconfigures a plugin that is **already installed**: it prints
   `already installed` and still writes the value. The short-circuit message is
   about the install, not the config write. Do **not** `claude plugin uninstall` to
   reconfigure: uninstalling drops this plugin's whole stored `pluginConfigs` entry,
   resetting every option in the table above to its default. `-s` defaults to `user`,
   so pass the scope `claude plugin list` reports for this plugin. The verified-version
   record lives in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-reconfiguration/README.md).

   The value is stored immediately; the session you are in does not change. Hooks are
   handed their `CLAUDE_PLUGIN_OPTION_*` when the session starts, so start a fresh
   Claude Code session before expecting new behavior. A check run in the old session
   still reports the old value, and that is not a failed write.

3. **By hand, in settings.** Add the value under `pluginConfigs` in your **user**
   settings (`~/.claude/settings.json`):

   ```json
   {
     "pluginConfigs": {
       "testing@<marketplace>": {
         "options": {
           "test_guards_enabled": <value>
         }
       }
     }
   }
   ```

   Plugin option values are read from **user**, `--settings`, and managed settings
   only, **not** from a project's `.claude/settings.json`. To vary behavior per
   repository, enable or disable the plugin in that project's `enabledPlugins`
   instead of setting an option there.

Do not set the `CLAUDE_PLUGIN_OPTION_*` variables yourself. They are how Claude Code
hands a configured value to a hook process; the value comes from the routes above.

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins-reference#user-configuration): the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin install options](https://code.claude.com/docs/en/plugins-reference#plugin-install): the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills): `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect): user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/discover-plugins#manage-installed-plugins): enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->

## License

MIT (SPDX-License-Identifier: MIT).
