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
