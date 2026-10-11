# Upstream source: Claude Haiku 5.5 launch and system card

## Contents

- [Source and verification](#source-and-verification)
- [Launch page figures](#launch-page-figures)
- [System card findings](#system-card-findings)
- [Independent measurements](#independent-measurements)
- [Decisions](#decisions)

This is the provenance record for this repository's response to the Claude Haiku 5.5 release
(2026-10-07). It follows the record shape of [opus-5-5-task-cost.md](opus-5-5-task-cost.md) and the
[upstream-drift](../conventions/upstream-drift/README.md#required-parts) convention. Figures from the
launch page and the system card appear only in this file, each labeled vendor-reported; figures from
independent measurers are labeled with their publisher. Guidance elsewhere links this record and
copies none of its figures ([cost claims](../../.claude/rules/cost-claims.md)).

## Source and verification

- Correlate: the launch page, <https://www.anthropic.com/claude-haiku-5-5>, published 2026-10-07,
  read 2026-10-10 from the page's own benchmark table and chart data.
- Correlate: the system card, <https://www.anthropic.com/claude-haiku-5-5-system-card> (redirects to
  the card PDF), published 2026-10-07, text extracted and searched 2026-10-10.
- Pointers for model facts: [What's new in Claude Haiku 5.5](https://platform.claude.com/docs/en/models/haiku-5-5/whats-new-haiku-5-5),
  [Models overview](https://platform.claude.com/docs/en/about-claude/models/overview),
  [Prompting Claude Haiku 5.5](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-haiku-5-5)
  and [model config: model aliases](https://code.claude.com/docs/en/model-config#model-aliases),
  each read as raw markdown on 2026-10-10.
- Evidence standing: the launch page, the system card and the docs are one publisher for facts
  about Anthropic's own model. Each independent measurement below is a single source.
- **As of**: 2026-10-10
- **Recheck trigger**: Anthropic publishes a revised Haiku 5.5 system card, or Haiku 4.5 retires
  (the provider alias rows and every comparison against Haiku 4.5 below change meaning then).

## Launch page figures

All vendor-reported, from the launch page's benchmark table. The table also carries a GPT-6 Luna
column, not recorded here, and has no Opus 5.5 or Fable column.

| Benchmark | Haiku 5.5 | Haiku 4.5 | Sonnet 5.5 |
|---|---|---|---|
| GDPval-AA v2.1 (run by Artificial Analysis) | 1620 | 735 | 1840 |
| AA-Briefcase v1.1 | 1578 | 614 | 1824 |
| OSWorld 2.1, offline subset | 72.4% | 15.7% | 83.9% |
| Humanity's Last Exam, no tools | 45.9% | 10.2% | 56.9% |
| Humanity's Last Exam, with tools | 57.4% | 18.7% | 64.5% |
| Terminal-Bench 4.0 | 39.2% | 0.0% | 70.6% |
| FrontierCode 1.1 (Main) | 46.4% | not reported | 52.1% (at xhigh) |
| Chartography, no tools | 46.4% | 6.4% | 61.6% |

Terminal-Bench 4.0 by effort level, vendor-reported from chart data: the Haiku 5.5 and Sonnet 5.5
rows from the Haiku 5.5 launch page, the Opus 5.5 row from the Sonnet 5.5 launch page
(<https://www.anthropic.com/claude-sonnet-5-5>, read 2026-10-10). The table's Terminal-Bench
figures above are the max-effort points.

| Model | low | medium | high | xhigh | max |
|---|---|---|---|---|---|
| Haiku 5.5 | 12.7% | 20.3% | 24.8% | 31.5% | 39.2% |
| Sonnet 5.5 | 20% | 28.8% | 43% | 61.5% | 70.6% |
| Opus 5.5 | 38.5% | 57.6% | 64.2% | 66.4% | 64.8% |

No source explains Haiku 4.5's 0.0%.

The launch page also says Haiku 5.5 costs around 75% less to run than Haiku 4.5 on average
(vendor-reported; no docs page states it as of 2026-10-10).

## System card findings

All vendor-reported, from the system card:

- **Capability placement** (section 2.2.4, from the chemical and biological risk evaluations):
  above Sonnet 5, below Opus 5, and well below Mythos 5.1, Sonnet 5.5 and Opus 5.5, with a relative
  deficit on complex, iterative tasks.
- **Over-refusal** (section 6.2.2): it over-refused more than any other model tested in the
  automated behavioral audit, Haiku 4.5 included, while over-refusing less than Haiku 4.5 on
  single-turn benign requests (section 4.1.2).
- **Unreported shortcuts** (summary): it used a leaked answer without telling the user more often
  than Haiku 4.5.

## Independent measurements

Each is a single third-party source, labeled by publisher:

- **Vals AI**: Terminal-Bench 4.0 at max effort, 35.35% (rank 12 of 45), on its own harness
  (<https://www.vals.ai/models/anthropic_claude-haiku-5-5>, 2026-10-08). A 32.8% figure attributed
  to Artificial Analysis in a repost does not appear on Artificial Analysis's own page and is not
  recorded.
- **Artificial Analysis**: Intelligence Index 43 at max effort, second of 180 models in its class
  against a class median of 13; the page publishes no coding or agentic index for the model
  (<https://artificialanalysis.ai/models/claude-haiku-5-5>, undated page, read 2026-10-10).
- **Bug Hunt Bench** (Pawel Huryn, Product Compass, shown by BenchLM for reference only): verified
  fixes for Haiku 5.5 against Sonnet 5.5, 21.5 against 51.3 at max effort and 18.3 against 36.0 at
  xhigh, over 105 bugs in two TypeScript repositories run in Claude Code with blind judging; the
  Haiku max figure is the mean of two runs
  (<https://benchlm.ai/md/benchmarks/bug-hunt-bench.md>, 2026-10-08).

## Decisions

Each row is our decision in our own words. Shared for every row: **As of** 2026-10-10;
**Recheck trigger** as in [Source and verification](#source-and-verification), or the row's pointer
section changes.

| Topic | Ours | Pointer |
|---|---|---|
| H1 Routing | No role routes to `haiku` until it passes this repository's routing eval ([#6901](https://github.com/melodic-software/claude-code-plugins/issues/6901)); a role that does runs at `high`, never `xhigh` or `max`: [routing rubric](../../plugins/multi-agent/reference/routing-rubric.md) | [Choosing a model](https://platform.claude.com/docs/en/about-claude/models/choosing-a-model#decide-whether-to-upgrade-or-change-models) |
| H2 Effort and the `haiku` alias | The plugin-philosophy effort carve-out separates the Anthropic API, where `haiku` takes an effort level, from providers where it still resolves to Haiku 4.5: [effort tiers](../plugin-philosophy.md#effort-tiers) | [model config: model aliases](https://code.claude.com/docs/en/model-config#model-aliases); [adjust effort level](https://code.claude.com/docs/en/model-config#adjust-effort-level) |
| H3 Loop lanes | `haiku` stays out of every lane on four grounds, none of them context window or knowledge cutoff: [Alias binding](../conventions/loop-lane/README.md#alias-binding) | [Prompting Claude Haiku 5.5](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-haiku-5-5); the system card above <!-- ai-slop-ignore: factual model spec, not assistant-frame disclaimer --> |
| H4 Instruction audit | The standing schedule row `frontier-release-instruction-ablation` runs `/harness-config:audit-instructions` on any Claude model release and `/harness-config:unhobble` only on a frontier release; Haiku 5.5 got the audit pass only ([#2019](https://github.com/melodic-software/claude-code-plugins/issues/2019)) | none: an in-repo decision |
