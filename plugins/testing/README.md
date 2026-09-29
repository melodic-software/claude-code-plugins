# testing

A Claude Code plugin for the **test stage** of a disciplined dev workflow. Plan
what needs testing, author tests at the right level, verify the running app
end-to-end, diagnose failures to root cause, and catch tests that cannot fail. Seven
skills, one concern: proving behavior with tests.

| Skill | What it does |
|---|---|
| `/testing:plan` | Coverage-gap analysis. Classify changed files by required test type, identify gaps, prioritize by regression risk. |
| `/testing:write` | Test authoring discipline. Vertical-slice TDD, test-type selection, naming, placement, fixture patterns, four-pillars assessment. |
| `/testing:run-e2e` | Live app verification. Start the app via the project's orchestrator, drive UI/API flows with token-efficient browser automation, capture evidence; includes a non-UI smoke-test playbook (MCP stdio handshake, shell/PowerShell surfaces). |
| `/testing:diagnose` | Failing-test diagnosis. Failure classification, root-cause analysis (never retry blindly), then the reproduce → isolate → fix → retest → regression loop. |
| `/testing:audit` | Can't-fail test detection, a deterministic script finds assertion-free bodies, self-identical (recomputed-expectation) assertions, and mock-only oracles across JS/TS, Python, C#, Bash, PowerShell and Go; reports with a coverage denominator, gates fail-closed via `--check`, and opt-in persists findings for a review fix pass. |
| `/testing:setup` | Configure the can't-fail checks: `check` prints the resolved `.claude/testing.yaml`, the test-lint rules missing per language, an optional instruction line to paste, and a settings hook entry for test globs the shipped hook skips; `apply` writes `.claude/testing.yaml`. |
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

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install testing@melodic-software
```

## Configuration

Test structure and conventions come from your own project's `CLAUDE.md` and rules.

Two `userConfig` options, prompted by Claude Code at enable time:

- `test_guards_enabled` (default `false`) turns on two hooks. `test-scan` (PostToolUse) runs the
  can't-fail scanner on each test file Claude writes or edits and returns the findings as
  context. `test-weaken` (PreToolUse) asks Claude for a reason when an edit removes or skips tests
  or assertions.
- `stdin_read_timeout` (default `2` seconds) bounds how long a hook waits on its input before it
  fails open.

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

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `test_guards_enabled` | boolean | `false` | `CLAUDE_PLUGIN_OPTION_TEST_GUARDS_ENABLED` | Scan each test file Claude writes or edits for tests that cannot fail, and ask Claude for a reason when an edit removes or skips tests or assertions. Off by default. |
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
