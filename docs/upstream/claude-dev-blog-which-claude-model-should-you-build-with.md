# Upstream source: "Which Claude model should you build with?" (claude.dev)

This page records what this repository takes from, adapts, already has, or rejects in the
claude.dev guide
[Which Claude model should you build with?](https://claude.dev/blog/which-claude-model-should-you-build-with)
(no license stated). Rows hold our decisions and our own descriptions of each idea, under the
upstream-drift convention's
[What a row may describe](../contracts/upstream-drift/README.md#what-a-row-may-describe); read the
guide at each row's link for what it says. This record copies no figure, price or table from the
guide: per [cost-claims](../../.claude/rules/cost-claims.md), rates live on the pricing page.

The guide is a blog post. Where a docs section covers a topic, our surfaces point at that section
and cite the guide only as a correlate; existing citations of the guide in
`plugins/planning/skills/plan/context/plan-template.md`, `docs/plugin-philosophy.md`,
`plugins/multi-agent/reference/routing-rubric.md`, `plugins/multi-agent/reference/defaults.yaml`,
`plugins/multi-agent/reference/config.md` and `plugins/implementation/agents/scoped-implementer.md`
stay as they are.

- **Pointer**: when re-auditing a row, fetch
  <https://claude.dev/blog/which-claude-model-should-you-build-with> live at the section the row
  links.
- **As of**: 2026-11-11
- **Recheck trigger**: the post is revised, or a later claude.dev post on model choice supersedes
  it.

## Attribution table

**Stated**: the guide gives this problem at the label's link. **Inference**: we derived it from the
mechanism. Disposition is `take`, `adapt`, `already have` or `reject`, with the reason.

| Idea (section) | What it does | Upstream problem, motivation, goal | Our problem | Disposition |
|---|---|---|---|---|
| [Starting model](https://claude.dev/blog/which-claude-model-should-you-build-with#tldr) | Names a mid-tier default for most work and the top tier for the hardest or longest work. | Readers need one place to start before tuning. **Stated** ([TL;DR](https://claude.dev/blog/which-claude-model-should-you-build-with#tldr)) | Which tier our heavy agents and lanes bind by default: `plugins/implementation/agents/implementer.md:8`, [Model tiers](../plugin-philosophy.md#model-tiers) | **already have:** the implementer binds `opus`; `frontier: fable` in `plugins/multi-agent/reference/defaults.yaml` marks the top tier for the fan-out guard. |
| [Effort before model](https://claude.dev/blog/which-claude-model-should-you-build-with#tldr) | Tunes effort first and changes model only when effort cannot close the gap. | Effort is a cheaper, finer control than a model swap. **Stated** ([TL;DR](https://claude.dev/blog/which-claude-model-should-you-build-with#tldr)) | A lane that falls short: [Model tiers](../plugin-philosophy.md#model-tiers) rule 1 | **already have:** rule 1 orders self-check, then effort, then a second model. |
| [Escalation ladder](https://claude.dev/blog/which-claude-model-should-you-build-with#latency-against-accuracy) | Orders the fixes for a weak result and resets effort when moving up a tier. | Avoid paying the larger model's top effort when its lower effort suffices. **Stated** ([latency against accuracy](https://claude.dev/blog/which-claude-model-should-you-build-with#latency-against-accuracy)) | Rule 1 lacked the effort reset: `docs/plugin-philosophy.md` Model tiers | **adapt:** rule 1 now starts the second model below the effort the first reached; its existing pointer covers the source. |
| [Task table](https://claude.dev/blog/which-claude-model-should-you-build-with#pick-a-model-by-task) | Maps task kinds to a starting model and effort. | Readers want a lookup by kind of work. **Stated** ([pick a model by task](https://claude.dev/blog/which-claude-model-should-you-build-with#pick-a-model-by-task)) | Role defaults: `plugins/multi-agent/reference/defaults.yaml` | **already have:** cited as context in `defaults.yaml` reasons and `routing-rubric.md`; its Haiku rows are rejected below. |
| [Model comparison table](https://claude.dev/blog/which-claude-model-should-you-build-with#the-four-models-side-by-side) | Lists each model's rates, limits and defaults side by side. | One view of the trade space. **Inference** | none | **reject:** rates and limits belong to the pricing and model-config docs; copying them breaks [cost-claims](../../.claude/rules/cost-claims.md). |
| [Cost per finished task](https://claude.dev/blog/which-claude-model-should-you-build-with#capability-and-cost-per-finished-task) | Judges models by what a completed task costs, including the hardest tasks. | Token price misleads about task cost. **Stated** ([capability and cost](https://claude.dev/blog/which-claude-model-should-you-build-with#capability-and-cost-per-finished-task)) | Routing changes need a task-level measure: `plugins/multi-agent/reference/routing-rubric.md` The rule | **already have:** the routing eval judges tokens per completed task with retries counted. |
| [Lean main context](https://claude.dev/blog/which-claude-model-should-you-build-with#context-against-cost) | Keeps the costly model's context for decisions and hands verbose reads to subagents. | Each turn resends context, so a large one costs more on a bigger model. **Stated** ([context against cost](https://claude.dev/blog/which-claude-model-should-you-build-with#context-against-cost)) | When to delegate reading: [claude-com-fold-subagents.md](claude-com-fold-subagents.md) | **already have:** that record and Model tiers rule 2. |
| [Switch at a natural break](https://claude.dev/blog/which-claude-model-should-you-build-with#switch-at-a-natural-break) | Times a model change to a compaction or fresh session. | Changing models discards the cache, so the next turn rewrites it. **Stated** ([switch at a natural break](https://claude.dev/blog/which-claude-model-should-you-build-with#switch-at-a-natural-break)) | The user-scope routing rules suggest a model switch with no timing | **adapt:** lands in `melodic-software/dotfiles` `dot_claude/CLAUDE.md.tmpl` (separate PR), not in this repository. |
| [Small models for subagents](https://claude.dev/blog/which-claude-model-should-you-build-with#put-subagents-on-smaller-models) | Runs side-task subagents, Explore included, on the smallest tier. | Cheap side work should not bill at the main model's rate. **Stated** ([put subagents on smaller models](https://claude.dev/blog/which-claude-model-should-you-build-with#put-subagents-on-smaller-models)) | Retrieval role model: `plugins/multi-agent/reference/routing-rubric.md` | **reject:** no role routes to Haiku by owner rule; retrieval stays on `sonnet`. |
| [Edits kept on the lead model](https://claude.dev/blog/which-claude-model-should-you-build-with#put-subagents-on-smaller-models) | Limits small subagents to work whose mistakes are easy to catch. | A misread by a cheap helper wastes the main model's turns. **Stated** ([put subagents on smaller models](https://claude.dev/blog/which-claude-model-should-you-build-with#put-subagents-on-smaller-models)) | `worker.workloads.mechanical` routes to `sonnet` in `plugins/multi-agent/reference/defaults.yaml` | **adapt:** a single code edit stays on the session model (`melodic-software/dotfiles` `dot_claude/CLAUDE.md.tmpl`); `worker.workloads.mechanical` stays on `sonnet` because it is bulk independent fan-out, which the guide's [delegate bulk work](https://claude.dev/blog/which-claude-model-should-you-build-with#delegate-bulk-work-to-cheaper-workers) section allows. |
| [`opusplan`](https://claude.dev/blog/which-claude-model-should-you-build-with#put-subagents-on-smaller-models) | Plans on the larger model and edits on the smaller one. | The alias reverses the edit-placement advice, so it needs measuring. **Stated** ([put subagents on smaller models](https://claude.dev/blog/which-claude-model-should-you-build-with#put-subagents-on-smaller-models)) | Plan model split: `plugins/planning/skills/plan/context/plan-template.md` | **already have:** the template points at the `opusplan` setting; no default adopts it. |
| [Advisor pairing](https://claude.dev/blog/which-claude-model-should-you-build-with#escalate-hard-decisions-to-an-advisor) | Lets a cheap executor consult a stronger model mid-task. | Get top-tier judgment while paying mostly executor rates. **Stated** ([escalate to an advisor](https://claude.dev/blog/which-claude-model-should-you-build-with#escalate-hard-decisions-to-an-advisor)) | Whether a role needs an advisor: `routing-rubric.md` The rule | **already have:** no advisor is required; Model tiers rule 3 reads the advisor capability rule. |
| [Lead over cheap workers](https://claude.dev/blog/which-claude-model-should-you-build-with#delegate-bulk-work-to-cheaper-workers) | Splits work too large for one context across parallel cheaper workers. | Bulk independent work runs cheaper in parallel. **Stated** ([delegate bulk work](https://claude.dev/blog/which-claude-model-should-you-build-with#delegate-bulk-work-to-cheaper-workers)) | Fan-out routing: Model tiers rule 2, `fanout` in `defaults.yaml` | **already have:** delegate only independent bulk work. |
| [Top-tier lead of many subagents](https://claude.dev/blog/which-claude-model-should-you-build-with#pick-a-model-by-task) | Puts the top tier at the head of a large fan-out. | The hardest coordination gets the strongest model. **Inference** | Orchestrator model: `defaults.yaml` `roles.orchestrator` | **reject as default:** the orchestrator inherits the session model, following the [cost page's measurement](https://platform.claude.com/docs/en/about-claude/models/optimizing-for-cost-and-intelligence#orchestrator-strategy-delegate-bulk-work). |
| [Migration compatibility](https://claude.dev/blog/which-claude-model-should-you-build-with#check-compatibility-before-migrating) | Lists request-shape differences to test before changing an API model. | A model swap can break requests built for another model. **Stated** ([check compatibility](https://claude.dev/blog/which-claude-model-should-you-build-with#check-compatibility-before-migrating)) | none: this repository builds no API requests | **reject:** no surface here sends Messages API requests. |
| [Measure on your own work](https://claude.dev/blog/which-claude-model-should-you-build-with#measure-on-your-own-work) | Tests candidate models and efforts on real tasks before switching. | Published benchmarks only pick a starting point. **Stated** ([measure on your own work](https://claude.dev/blog/which-claude-model-should-you-build-with#measure-on-your-own-work)) | Evidence for a routing change: `routing-rubric.md` routing eval | **already have:** the eval in [#6901](https://github.com/melodic-software/claude-code-plugins/issues/6901). |

## License notice

The post states no license. Nothing from it is copied: this record holds ideas and links only.

- **Pointer**: <https://claude.dev/blog/which-claude-model-should-you-build-with>, checked for a
  license statement.
- **As of**: 2026-11-11
- **Recheck trigger**: the post or the claude.dev site adds a license statement.
