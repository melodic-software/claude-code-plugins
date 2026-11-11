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
  `cases.jsonl` + README for an LLM application, or `case.yaml` cases in the plugin's `evals/`
  directory for a Claude Code skill you author. Grading-hygiene gate before finishing (different
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

`claude plugin eval` is what runs and scores a plugin's eval cases. For what one run does and what
it reports, read
[How an eval run works](https://code.claude.com/docs/en/plugin-evals#how-an-eval-run-works) live.
It needs a recent Claude Code; for the minimum version, see
[Requirements](https://code.claude.com/docs/en/plugin-evals#requirements). Every run and every
judge grader is a metered model call on your own account.

This plugin is the practice around that command rather than a second runner. `/evals:plugin-eval`
preflights the machine and the target, validates the case files, prices the suite before it spends,
and reads the delta out of the result JSON. `/evals:validate` is the zero-spend half of the same
work.

Here `/evals:design` writes a skill's cases and `claude plugin eval init` a whole plugin's, both in
the suite layout the CLI reads, and `/evals:validate` checks them. For that layout, read
[Write a case manually](https://code.claude.com/docs/en/plugin-evals#write-a-case-manually) live.
This repository converts
`skill-creator` `evals.json` cases into the suite rather than keeping both:
`skills/plugin-eval/scripts/convert-evals-json.py <plugin-dir>` converts one plugin's `evals.json`
cases into its `evals/` suite and removes the converted files.

## Shared grader matchers

A `regex` or `tool_used` grader is static text in `case.yaml`, so the binary cannot call a helper
when it grades. Shapes that recur across cases live once in `matchers/fragments.json` instead, and a
case builds a grader from them in `<case>/matchers.json`:

```json
{"no-token-shell": [{"use": "command_position"}, "(?:curl|wget)\\b",
                    {"use": "token_argument"}, "AbCdEfGhIjKlMnOp"]}
```

Each part is literal regex or a fragment, joined in order; `"with": {"row": "..."}` fills a
fragment's `{{row}}` slot. The fragments cover mechanically exact shapes only:

| Fragment | Matches |
|---|---|
| `command_position` | a Bash command string up to where a command starts (POSIX shells) |
| `command_position_multishell` | the same, also through PowerShell, `cmd /c`, `python -m`, `$(` |
| `command_anywhere` | anywhere inside the Bash command string |
| `token_argument` | the rest of the same simple command, up to a token |
| `table_header_rule` | a Markdown table's header rule line |
| `table_verdict_cell` | a table row naming `{{row}}` with a literal PASS/FAIL/INFO/WARN cell |

A grader that judges a meaning (a refusal, a report, a pick) is an `llm` grader, not a fragment.

`skills/validate/scripts/check-matchers.py <eval-dir>...` fails when a fragment's samples or a
built grader's samples sort the wrong way under Python's `re` or node's `RegExp` (the binary's
engine), when a built grader has no must-pass and must-fail samples, or when the `case.yaml` text
differs from its build; `--write` rewrites the drifted lines. Its suite, `check-matchers.test.sh`,
runs it over every plugin's evals in CI.

To add a fragment, give it a `summary`, its `text`, a `probe` grader built from it, and `samples`
with answers that must pass and answers that must fail, near misses included. To build a grader,
write its `matchers.json` entry, run `check-matchers.py --write`, and add `samples/<grader>.json`.

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

Eight `userConfig` keys. Two set the run's cost ceiling, read by `/evals:plugin-eval`:

- **`max_cost_usd`** (number, default `5`): the ceiling passed to the CLI as `--max-cost-usd`.
  Raise it for a suite whose estimate is higher. For what the ceiling bounds and what a run that
  reaches it returns, read the `--max-cost-usd` row of
  [Command options](https://code.claude.com/docs/en/plugin-evals#command-options) live.
- **`unlimited_cost`** (boolean, default `false`): removes the ceiling and nothing else. The
  estimate still prints before the run, so an expensive suite is still visible before it starts.

Six set how evals are designed and read. Each default follows Anthropic's published eval guides;
where this repository departs from a source, the record is in the methodology skill's
`reference/local-decisions.md`.

- **`split_policy`** (string, default `train-test`): `reporting-only` also holds back a split that
  no keep-or-revert decision or final pick reads, used only to report the result.
- **`interval_method`** (string, default `normal`): `wilson` or `jeffreys` changes the interval on
  the count of passing cases. Score intervals stay normal.
- **`review_format`** (string, default `markdown`): `html` renders the case review as one escaped
  page instead.
- **`grader_run_twice`** (boolean, default `true`): reports judge-vote agreement per `llm` grader
  from votes the run already took.
- **`same_model_warning`** (boolean, default `true`): warns when the tested model and the judge are
  the same model.
- **`labeled_grader_check`** (boolean, default `false`): adds a check of each grader against cases
  you label.

No hooks and no MCP servers. The methodology, design, and validate surfaces make no network calls
and no model calls; a `claude plugin eval` run does, on your own account, which is what the estimate
and the ceiling exist for. The one other outbound surface is the maintainer-only
`/evals:methodology update` action, which re-fetches the two upstream Anthropic doc pages to
drift-check the distilled reference files.

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. For how Claude Code asks for
these and hands them to the plugin, see [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration).

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `max_cost_usd` | number<br>*min 0* | `5` | Ceiling /evals:plugin-eval passes to the CLI as --max-cost-usd. Raise it for a suite whose estimate exceeds it. What the flag bounds: <https://code.claude.com/docs/en/plugin-evals#command-options> |
| `unlimited_cost` | boolean | `false` | Drop --max-cost-usd from the invocation so a suite always runs to completion. The estimate is still printed before the run; only the ceiling goes away. |
| `split_policy` | string | `"train-test"` | How eval cases split when a skill or prompt is tuned against them. train-test (the default) splits train and test as the bundled hillclimb guide does; reporting-only also holds back a split that no keep-or-revert decision or final pick reads, used only to report the result. |
| `interval_method` | string | `"normal"` | Interval the noise report puts on the count of cases that pass the threshold. normal (the default) uses the normal approximation; wilson uses the Wilson score interval; jeffreys uses the Jeffreys interval. Score intervals and the with-versus-without difference always use normal. |
| `review_format` | string | `"markdown"` | Format /evals:design renders candidate eval cases in for your approval. markdown (the default) is a table plus one fenced block per case; html is one page with every field escaped. |
| `grader_run_twice` | boolean | `true` | When on, /evals:plugin-eval's noise report shows how often the judge votes for each llm grader agreed, read from votes the run already took, at no extra spend. |
| `same_model_warning` | boolean | `true` | When on, /evals:plugin-eval's preflight warns when the tested model and the judge model resolve to the same model, and /evals:design repeats the reminder beside the build-eval route. |
| `labeled_grader_check` | boolean | `false` | When on, /evals:design checks a grader against a set of cases you label, not only the handful-of-cases agreement check. |

### How to set these

Set the options above for `evals@<marketplace>`, replacing `<marketplace>` with the
marketplace you installed this plugin from:

- **In a session or headless:** [`/plugin` in a session](https://code.claude.com/docs/en/plugins/cli-reference#plugin-in-a-session) or
  [`claude plugin configure`](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure). The configure command is the preferred
  headless route in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/plugin-reconfiguration/README.md), which records its limits.
- **By hand:** under [`pluginConfigs`](https://code.claude.com/docs/en/settings-reference#pluginconfigs) in your **user** settings.

Do **not** uninstall the plugin to reconfigure it: see [What an uninstall deletes and keeps](https://code.claude.com/docs/en/plugins/cli-reference#what-an-uninstall-deletes-and-keeps).
For a Claude Code release without `plugin configure`, see [Plugin install](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install).

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration)
- [Plugin configure](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure)
- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install)
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills)
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect)
- [Manage installed plugins](https://code.claude.com/docs/en/plugins/install#manage-installed-plugins)

<!-- END GENERATED: plugin options -->
