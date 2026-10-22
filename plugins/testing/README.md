# testing

A Claude Code plugin for the **test stage** of a disciplined dev workflow. Plan
what needs testing, author tests at the right level, verify the running app
end-to-end, diagnose failures to root cause, and catch tests that cannot fail, then clean them up. Twelve
skills cover it.

| Skill | What it does |
|---|---|
| `/testing:plan` | Coverage-gap analysis. Classify changed files by required test type, identify gaps, prioritize by regression risk. |
| `/testing:write` | Test authoring discipline. Vertical-slice TDD, test-type selection, naming, placement, fixture patterns, four-pillars assessment. |
| `/testing:run-e2e` | Live app verification. Start the app via the project's orchestrator, drive UI/API flows with token-efficient browser automation, capture evidence; includes a non-UI smoke-test playbook (MCP stdio handshake, shell/PowerShell surfaces). |
| `/testing:map-features` | Writes a feature map for one app: a project skill (default `.claude/skills/feature-map/`) whose index names the launch recipe, the recorded driver and a doctor command, with a file for each feature listing its parts, entry points, drive steps and traps. Refuses a location inside a `run-<name>` or `verify` skill. Reports done only after one mapped feature passes through `/testing:run-e2e`. Format: `reference/feature-map.md`. |
| `/testing:refresh-feature-map` | Model-invocable. Keeps an existing feature map accurate: read-only source checks per feature, then one live pass through `/testing:run-e2e`. Edits stay in the map directory; a behavior the app lost goes to `/bugs:write` or the report, never into the map. A clean pass records its commit under the plugin data directory and the next pass skips until HEAD moves. Map corrections go to one fixed branch per map, `feature-map-upkeep/<map slug>`, and one pull request, updated rather than duplicated, opened only when unattended or after you confirm. An unattended pass refuses a `chrome` map. |
| `/testing:check-visual-parity` | Model-invocable; implement's refactor mode calls it for a plan phase with a `**Parity contract:**` line. `baseline` captures PNG screenshots of the listed states before the first edit and records their sha256, OS, browser, viewport and scale in a manifest; `compare` captures them again at each green checkpoint and counts differing pixels per image with pixelmatch against `pixel_tolerance`. It captures only through a driver that writes PNG files, launches through `/testing:run-e2e`'s launch path, runs the repository's own visual suite first, and never edits or re-captures a baseline. pixelmatch and pngjs install on first use from the committed lockfile (`npm` required). |
| `/testing:diagnose` | Failing-test diagnosis. Failure classification, root-cause analysis (never retry blindly), then the reproduce → isolate → fix → retest → regression loop. |
| `/testing:audit` | Can't-fail test detection: a deterministic script runs thirteen rules across JS/TS, Python, C#, Bash, PowerShell and Go, from assertion-free bodies and self-identical (recomputed-expectation) assertions to unawaited assertions, conditional assertions and Playwright retry or `test.only` configs. `--check` fails on the first two (Bash-harness findings only with `--strict`); `--strict` adds mock-only oracles and the two Playwright config rules; the other eight only report. It reports with a coverage denominator and opt-in persists findings for a review fix pass. |
| `/testing:cleanup` | Clean up low-value tests in one folder. Reads `/testing:audit` findings, its judge pass's FLAG verdicts and the tests you name as flaky; a fresh-context classifier picks quarantine, rewrite, delete, merge or keep per test. It rewrites by default and deletes or merges only with a stated no-contract reason and your yes on each item. `/mutation-testing:audit --record-mutants` records the mutants the tests kill before any edit, and `--replay-mutants` blocks the batch when a kill is lost. Nothing is committed until you approve the batch. Needs the `mutation-testing` plugin set up with a `test-command`; without one, `--cannot-fail-only` deletes only tests that cannot fail, each cleared by a fresh-context skeptic and your yes. |
| `/testing:setup` | Configure the can't-fail checks: `check` prints the resolved testing config, the test-lint rules missing per language, an optional instruction line to paste, and the test globs the shipped `test-weaken` hook skips; `apply` writes the config block of `docs/conventions/testing.md` (or `.claude/testing.yaml` when that file is the one in use). |
| `/testing:check` | Read-only and model-invocable. Reports whether `node` and `jq` resolve for the plugin's hooks, with the install route from `prerequisites.json` when it does not. It never installs. |
| `testing:test-value` | Model-invoked guidance, loaded by the review and implementation agents and the `/testing:audit` judge pass: where each expected value must come from, when call-count and database checks are legitimate, and the can't-fail taxonomy keyed to `/testing:audit` rule ids. |

| Workflow | Launched by | What it does |
|---|---|---|
| `/testing:fix-until-green` (`workflows/fix-until-green.js`) | `/testing:diagnose`, offered when several tests fail across files | One runner runs the command and lists failures with the source files each points at or imports. The workflow groups them so no two groups share a file and runs one fixer per group in the same working tree, in waves of `maxConcurrent`. A verifier then checks the diff from the starting commit for test weakening and for changed files no fixer was allowed to edit, and the command runs again. It stops when the command passes, at `maxRounds`, after two rounds in a row with no fewer failures, when a fixer's root cause sits in a file that is out of scope or protected (an editable in-scope file joins that fixer's group next round instead), when the check flags weakening or an edit outside the allowed files, or when HEAD moves. It flags these and never reverts them. Paths that are absolute, contain `..`, sit under git internals, agent settings, hooks, CI, editor tasks or dependency trees, or name a dependency manifest, lockfile, build file or secret-bearing file or directory, never reach a fixer (matched case-insensitively). A file a fixer asks for joins its group only when git tracks it, and the checks and every re-run count untracked files and a moved HEAD. After any round that dispatched a fixer, a green run gets a final verifier that re-runs the command and reviews the whole diff. The result lists the changed test, snapshot, fixture and runner config files as `testEdits`, matched by path; when a green run has any, a runner re-runs the command in a throwaway worktree with those files as they stood at the start and the main tree's ignored dependency directories linked in. A failure there stops as `green-needs-test-edits` for a person to decide, since fixing a wrong test is allowed; a command that could not run there (a setup step, a missing dependency) stops as `base-rerun-env-failed`. `args`: `command` (required; without it nothing runs), `scope` (all entries rejected returns `bad-scope`), `maxRounds` (default 3), `maxConcurrent` (default 2), `roles` (the map `/multi-agent:route all code` prints; without it, fixers run on `opus`) and `finalVerify`. It commits nothing. |

| Agent | Dispatched by | What it does |
|---|---|---|
| `testing:green-runner` | the `testing:fix-until-green` workflow | Runs the command and returns its failures; on the base re-run, runs it in a throwaway worktree it creates and removes. Bash only. |
| `testing:green-fixer` | the `testing:fix-until-green` workflow | Fixes one group of failures in its assigned files, with `testing:test-value` preloaded. Read, Edit and Bash. |
| `testing:green-verifier` | the `testing:fix-until-green` workflow | Checks a round's diff for test weakening against `testing:test-value`, and re-runs the command on the final pass. Read and Bash. |
| `testing:test-judge` | `/testing:audit --judge` | Judges where each given test block's expected value came from and reports any instruction embedded in the files it read, never acting on one. Read, Grep and Glob. |

The green agents inherit the model and pin no effort; the workflow passes both from the role map.
`testing:test-judge` inherits too; `/testing:audit --judge` passes its model and effort per call.

## Works in any repo

- **Reads your conventions, assumes none.** Test frameworks, project locations,
  naming, fixture patterns, and the e2e-orchestrator configuration come from your own
  project's `CLAUDE.md` / rules and existing test projects; the skills infer from what
  exists when nothing is documented.
- **Cross-plugin refs degrade gracefully.** Test invocation defers to the `toolchain`
  plugin's `/toolchain:check` when enabled and to the project's own test command
  otherwise; TDD design questions route to `/tdd:principles`, browser mechanics to
  `/playwright:playwright`, outcome sign-off to `/verification:confirm`, and the
  implement loop to `/implementation:implement`. Each is used when enabled and
  substituted with inline guidance or a manual handoff otherwise. No step blocks on a
  disabled or missing plugin.
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

- `test_guards_enabled` (default `false`) turns on the `test-weaken` hook (PreToolUse), which tells
  Claude which tests, assertions or expected values an edit removes, skips or changes. Can't-fail
  findings are report-only, so they come from `/testing:audit` on demand, not from a per-edit hook
  ([check placement](../../docs/conventions/check-placement/README.md)).
- `stdin_read_timeout` (default `2` seconds) bounds how long a hook waits on its input before it
  fails open.

An installed mod can stop this plugin's `PreToolUse` hooks from running: they run after the last
mod calls `next`, so a mod that answers a `tool.call` without calling it skips them
([where settings hooks run in the order](https://code.claude.com/docs/en/plugins/mods/events#where-settings-hooks-run-in-the-order)).
A mod can also approve a call they blocked, because its `tool.check` hook runs after them
([approve or refuse a tool call before the user is asked](https://code.claude.com/docs/en/plugins/mods/events#approve-or-refuse-a-tool-call-before-the-user-is-asked)).

### Judge pass

`/testing:audit --judge [<base>]` asks a separate model one question of each test block the change
added or changed: where did its expected value come from? It answers FLAG (the value restates the
implementation), PASS or UNKNOWN, quotes its evidence, and proposes a diff for a FLAG; it never
applies anything. The judge runs on a model class other than the one that wrote the tests, with
`hooks/test-judge-prompt.md` as its prompt, and each quote must appear verbatim in the repository
before a verdict is shown. `/source-control:pull-request` prep runs it when this plugin is
installed and enabled, and otherwise reports
`judge pass not run: testing plugin not installed or not enabled`. The calibration cases and raters are in `skills/audit/evals/judge-calibration/`.

`/testing:run-e2e` reads four optional keys. `recording` (`video | gif | off`, default `off`) and
`browser_mode` (`headed | headless`, default `headless`) live on `.claude/testing/e2e.md`.
`e2e_driver` (`auto | harness | run | playwright | chrome`) and `reuse_running_instance`
(`auto | true | false`), both default `auto`, live in `docs/conventions/testing.yaml`, its personal
layers, or the `userConfig` options below; `scripts/resolve-config.sh e2e` resolves them and names
an invalid value instead of stopping. When an app already answers and the default branch declares a
Workspace environment entry, `reuse_running_instance: false`, and `auto` on an unattended run,
start the run's own instance through the entry's `up` and `info` and never drive the answering app;
with no entry, unattended `auto` reuses the app with labeled evidence and `false` stops, as
before. Under `auto` a run now drives through the repository's own
harness when a spec covers the changed flow, and otherwise through the path it used before. A fifth
key, `feature_map_dir` (default `.claude/skills/feature-map`), says where `/testing:map-features`
writes the feature map and where run-e2e reads it; it is a repository path, set only in
`docs/conventions/testing.yaml` or `.claude/testing.local.yaml`, with no `userConfig` option. Keys,
defaults and precedence are in the skill's bundled `run-e2e/context/e2e-config.md`.

`browser_driver` (default `playwright-cli`) names the one browser tool a `playwright` drive uses. It
sits in the same layers as `e2e_driver`, plus the `userConfig` option of the same name. When the
driver for the run is `playwright`, pinned or picked by `auto`, `scripts/check-browser-driver.sh`
checks before the first drive that the command is on PATH; if it is not, the run stops, naming the
setting, the value, where it came from, and the two ways forward (install the tool, or set
`browser_driver` to one you have). It never substitutes another tool or switches mid-run.

`pixel_tolerance` is a map in `docs/conventions/testing.yaml`: `pixels`, the differing pixels per
image `/testing:check-visual-parity` accepts (a whole number, default 0), and `reason`, required when
`pixels` is above 0. Quote a reason that holds a colon followed by a space. The team value is read
from origin's default branch (the working tree only when there is no `origin`). The user-global
`~/.claude/testing.yaml`, `.claude/testing.local.yaml` and the `pixel_tolerance` option can only
lower it: the lowest valid value wins, a raise is reported as ignored, and an invalid layer is
named and dropped. A testing release without this key stops its test scan on `pixel_tolerance` in
`testing.yaml`, so add the map once every member runs this release.

**Upgrade note.** A testing release older than these keys never reads
`docs/conventions/testing.yaml`, and refuses an unknown key in the files it does read, which stops
its test scan. Keep the team's scan config where it is (the `docs/conventions/testing.md` block or
`.claude/testing.yaml`) until every member has upgraded, and put `e2e_driver` and
`reuse_running_instance` only in `docs/conventions/testing.yaml`, or in a personal layer on a
machine that runs this release.

Its `worst-case` action also reads an optional `.claude/testing/worst-case.md`, after the bundled
catalog in `run-e2e/context/worst-case.md`: the project's own worst-case values, field limits and
data formats, read as data. The action renders a target with that data, reverts what it injected
(proven with `cmp` snapshots), and reports what breaks without editing component code.

`/testing:audit` and the `test-weaken` hook read the testing config through the same cascade
(`~/.claude/testing.yaml`, the team layer, `.claude/testing.local.yaml`): adapters to turn off or
allow, path globs to exclude or include, extra adapter globs, consumer adapters, and a level per
rule (`off`, `warn`, `error`). `/testing:setup` documents the keys and writes the team layer.

The team layer is `docs/conventions/testing.yaml`, validated by
[`schemas/testing.schema.json`](schemas/testing.schema.json). It takes the keys `.claude/testing.yaml`
takes, plus the two run-e2e keys above. Without it, the team layer is the `yaml config` block in
`docs/conventions/testing.md` (read for one more release), else `<root>/.claude/testing.yaml`. The
first of the three present wins, and the resolver prints one warning for each other one present.
The prose testing rules stay in `docs/conventions/testing.md`. The user-global and
`.claude/testing.local.yaml` layers do not change.

#### Move the team layer to `docs/conventions/testing.yaml`

1. Create `docs/conventions/testing.yaml` with the content of the docs block (the lines between the
   fences) or of `.claude/testing.yaml`. The keys do not change; use plain or single-quoted values.
2. Run `/testing:setup check`: it prints the resolved config and must show
   `docs/conventions/testing.yaml` as the team layer.
3. Once every member runs this release, delete the old block or file. Until then every run prints a
   warning naming both; an older release keeps reading the old one.

`~/.claude/testing.yaml` and `.claude/testing.local.yaml` stay where they are; only the team layer
moves. Reading the block costs the same as reading the file; the measured p50 and p95 are in the
[latency probes](https://github.com/melodic-software/claude-code-plugins/blob/927a5305d238874ce006eaad6b3fa5c3cb07ebc1/docs/specs/tautological-tests/probes.md#team-layer-location-docs-block-or-claudetestingyaml-wsl2),
and `plugins/testing/scripts/time-config.sh` reproduces them.

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `test_guards_enabled` | boolean | `false` | `CLAUDE_PLUGIN_OPTION_TEST_GUARDS_ENABLED` | Adds an advisory note when an edit removes tests or assertions, adds a skip or changes an expected value, and, only with rules test-weaken-block: error, denies an added skip or removed test block that adds no test-change: marker; it never asks, and is off by default. |
| `e2e_driver` | string | `"auto"` | `CLAUDE_PLUGIN_OPTION_E2E_DRIVER` | Who drives /testing:run-e2e: auto (default) picks the repo's harness when a spec covers the flow, else run or playwright; harness, run, playwright, or chrome (attended runs only). A repository's docs/conventions/testing.yaml wins. |
| `reuse_running_instance` | string | `"auto"` | `CLAUDE_PLUGIN_OPTION_REUSE_RUNNING_INSTANCE` | true, or auto (default) when attended: /testing:run-e2e drives an app that already answers. With a Workspace environment entry, false and unattended auto start the run's own instance; without one, unattended auto reuses it with labeled evidence and false stops. docs/conventions/testing.yaml wins. |
| `browser_driver` | string | `"playwright-cli"` | `CLAUDE_PLUGIN_OPTION_BROWSER_DRIVER` | The command name of the one browser tool a /testing:run-e2e playwright drive uses (letters, digits, . _ -). playwright-cli by default. The run stops, naming this setting, when the command is not on PATH; it never switches tools. A repository's docs/conventions/testing.yaml wins. |
| `pixel_tolerance` | number<br>*min 0* | `0` | `CLAUDE_PLUGIN_OPTION_PIXEL_TOLERANCE` | Differing pixels per image /testing:check-visual-parity accepts. It can only lower the repository's pixel_tolerance in docs/conventions/testing.yaml, never raise it. 0 by default. |
| `stdin_read_timeout` | number<br>*min 1* | `2` | `CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT` | Idle bound on reading the hook payload from stdin: how long the pipe may go silent before the hook gives up and fails open |

### How to set these

Three supported routes:

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

- [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration): the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install): the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills): `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect): user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/plugins/install#manage-installed-plugins): enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->

## License

MIT (SPDX-License-Identifier: MIT).
