# evals

A Claude Code plugin that carries Anthropic's official LLM-evaluation guidance into any consumer
repo — distilled from a cover-to-cover reading of "Define success criteria and build evaluations"
(<https://platform.claude.com/docs/en/test-and-evaluate/develop-tests>) and its linked evals
cookbook (`anthropics/claude-cookbooks` `misc/building_evals.ipynb`), fetched 2026-08-08.

## Skills

- **`/evals:methodology <question>`** — knowledge router answering evaluation-design questions:
  what makes success criteria specific/measurable/achievable/relevant, how to quantify hazy
  qualities, eval anatomy (input/output/golden answer/score), edge-case taxonomy, the grading
  ladder (code > LLM > human), LLM-grader rubric practice, and six concrete recipes (exact match,
  cosine similarity, ROUGE-L, Likert, binary, ordinal). Four reference spokes load on demand; a
  quick decision guide answers the most common questions with no file load.
- **`/evals:design [app | skill <name>]`** — action skill that interviews for measurable success
  criteria first, then scaffolds a criteria doc plus a graded eval suite in your repo: a
  `cases.jsonl` + README for an LLM application, or an `evals/evals.json` (marketplace schema
  shape) for a Claude Code skill you author. Grading-hygiene gate before finishing (different
  grader model, constrained verdicts, sample-check the grader, stated re-run cost).

## What it deliberately does not do

No command in this plugin **executes** model-graded evals. Running is owned by your own tooling —
or, for Claude Code skill evals, by Anthropic's `skill-creator` plugin when you have it installed.
`skill-quality` (this marketplace) statically validates a skill's `evals/evals.json` when
installed.

## Upstream sync

The reference content distills a live Anthropic doc page. Every reference file carries a
"fetched YYYY-MM-DD" stamp; `/evals:methodology update` is the maintainer drift-check action that
re-fetches both sources, diffs, corrects, and refreshes the stamps.

## Eval-warrant verdicts

`design` warrants and ships evals (judgment-bearing interview/routing/refusal contract).
`methodology` is an explicit skip: pure-reference knowledge router with no decision contract, per
the migration playbook's warrant policy.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install evals@melodic-software
```

## Configuration

None. No hooks, no MCP servers, no userConfig. Consumer-facing use makes no network calls —
guidance and in-repo scaffolding only. The one outbound surface is the maintainer-only
`/evals:methodology update` action, which re-fetches the two upstream Anthropic doc pages to
drift-check the distilled reference files.
