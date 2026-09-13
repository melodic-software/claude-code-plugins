# evals

A Claude Code plugin that carries Anthropic's official LLM-evaluation guidance into any consumer
repo, distilled from a cover-to-cover reading of "Define success criteria and build evaluations"
(<https://platform.claude.com/docs/en/test-and-evaluate/develop-tests>) and its linked evals
cookbook (`anthropics/claude-cookbooks` `misc/building_evals.ipynb`), fetched 2026-08-08.

## Skills

- **`/evals:methodology <question>`** is the knowledge router for evaluation-design questions:
  what makes success criteria specific/measurable/achievable/relevant, how to quantify hazy
  qualities, eval anatomy (input/output/golden answer/score), edge-case taxonomy, the grading
  ladder (code > LLM > human), LLM-grader rubric practice, and six concrete recipes (exact match,
  cosine similarity, ROUGE-L, Likert, binary, ordinal). Four reference spokes load on demand; a
  quick decision guide answers the most common questions with no file load.
- **`/evals:design [app | skill <name>]`** is the action skill that interviews for measurable
  success criteria first, then scaffolds a criteria doc plus a graded eval suite in your repo: a
  `cases.jsonl` + README for an LLM application, or an `evals/evals.json` (marketplace schema
  shape) for a Claude Code skill you author. Grading-hygiene gate before finishing (different
  grader model, constrained verdicts, sample-check the grader, stated re-run cost).
- **`/evals:plugin-eval [preflight | validate | run | read <json> | ci | init]`**: guided practice
  around the `claude plugin eval` command. Preflight reports the CLI version against the floor the
  command requires, whether this machine has a sandbox backend, and what kind of target you pointed
  at; the case files are checked before anything spends; the suite is priced against your configured
  ceiling; the result is read delta first, with an iteration loop and a CI recipe.
- **`/evals:validate [<eval dir>]`**: static check over a plugin's eval case files. It reports the
  load failures the CLI rejects and the authoring mistakes its docs name, with no model call and no
  spend, so a broken suite is found before a run pays to discover it.

## What runs where

`claude plugin eval` is what runs and scores a plugin's eval cases: it loads the plugin, replays
each case with the plugin and again with nothing loaded, grades both arms, and reports `WITH`,
`W/OUT`, and the delta between them. It needs Claude Code v2.1.269 or later, and every run and every
judge grader is a metered model call on your own account.

This plugin is the practice around that command rather than a second runner. `/evals:plugin-eval`
preflights the machine and the target, validates the case files, prices the suite before it spends,
and reads the delta out of the result JSON. `/evals:validate` is the zero-spend half of the same
work.

Two eval formats coexist and are not interchangeable. The CLI reads a plugin's `evals/` tree
(`prompt.md` plus `graders/*.md`, or `case.yaml`). A Claude Code skill's own `evals/evals.json`, the
format `/evals:design` scaffolds, belongs to Anthropic's `skill-creator` plugin, which runs it;
`skill-quality` (this marketplace) statically validates it when installed.

## Upstream sync

The reference content distills a live Anthropic doc page. Every reference file carries a
"fetched YYYY-MM-DD" stamp; `/evals:methodology update` is the maintainer drift-check action that
re-fetches both sources, diffs, corrects, and refreshes the stamps.

## Eval-warrant verdicts

`design`, `plugin-eval`, and `validate` each warrant and ship evals: every one carries a
judgment-bearing routing or refusal contract. `methodology` is an explicit skip: pure-reference
knowledge router with no decision contract, per the migration playbook's warrant policy.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install evals@melodic-software
```

## Configuration

Two `userConfig` keys, both read by `/evals:plugin-eval`:

- **`max_cost_usd`** (number, default `5`): the ceiling passed to the CLI as `--max-cost-usd`. It
  bounds one invocation rather than a session's total, and a suite that reaches it stops partway
  with partial results, so raise it for a suite whose estimate is higher.
- **`unlimited_cost`** (boolean, default `false`): removes the ceiling and nothing else. The
  estimate still prints before the run, so an expensive suite is still visible before it starts.

No hooks and no MCP servers. The methodology, design, and validate surfaces make no network calls
and no model calls; a `claude plugin eval` run does, on your own account, which is what the estimate
and the ceiling exist for. The one other outbound surface is the maintainer-only
`/evals:methodology update` action, which re-fetches the two upstream Anthropic doc pages to
drift-check the distilled reference files.

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `max_cost_usd` | number<br>*min 0* | `5` | `CLAUDE_PLUGIN_OPTION_MAX_COST_USD` | Ceiling /evals:plugin-eval passes to the CLI as --max-cost-usd. It bounds one invocation, not a session's total, and a run that reaches it stops mid-suite with partial results. Raise it for a suite whose estimate exceeds it. |
| `unlimited_cost` | boolean | `false` | `CLAUDE_PLUGIN_OPTION_UNLIMITED_COST` | Drop --max-cost-usd from the invocation so a suite always runs to completion. The estimate is still printed before the run; only the ceiling goes away. |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively.** Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure evals@<marketplace>`.
2. **Headless.** Repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install evals@<marketplace> -s <scope> --config max_cost_usd=<value>
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
       "evals@<marketplace>": {
         "options": {
           "max_cost_usd": <value>
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
