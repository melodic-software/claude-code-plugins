# planning

A Claude Code plugin for the **pre-implementation planning pipeline** — everything
between a rough idea and approved, executable work. Eight pipeline skills covering
charting a too-big, foggy effort as a decision map, divergence, product intent, the
engineering contract, design exploration, the design→plan gate, adversarial review,
and the implementation plan itself — plus a re-runnable `setup` action that settles
where artifacts land in the consuming repo.

| Skill | Stage | What it does |
|---|---|---|
| `/planning:wayfind` | Chart | Charts a too-big-AND-foggy effort as a shared decision map on the work-item tracker, then works its frontier one decision at a time — routing each to the right skill — until the fog clears and a Brief / PRD / PLAN can be handed onward. Upstream of the whole pipeline. |
| `/planning:brainstorm` | Diverge | Turns a rough problem into codebase-grounded candidate approaches ordered cheapest→most ambitious; the user reacts, then work routes onward scoped. |
| `/planning:prd` | Product intent | Produces a Product Requirements Document (problem, users, success metrics) in three tiers — one-pager, consumer-feature, B2B-internal — with a synthesize path and a review mode. |
| `/planning:interview` | Engineering contract | Locks a task contract (goal, constraints, acceptance criteria, named assumptions) into a PLAN.md Brief — synthesizing when intent is clear, running frontier-rounds Q&A when it isn't, or interviewing relentlessly on request. |
| `/planning:questionnaire` | Person hand-off | Turns a decision another person holds into a discovery questionnaire delivered async — interviews the user about the send only (recipient, what's needed back), writes the document to the topic's memory slice, and leaves delivery out-of-band. |
| `/planning:draft-goal-condition` | Goal authoring | Crafts a paste-ready `/goal` completion condition from a stated intent — reads the current official `/goal` docs live for the condition shape and character limit (nothing hardcoded), drafts a transcript-demonstrable condition, and proves it fits the limit with a deterministic character counter instead of model guesswork; a lever-fit gate routes interval-shaped or cloud/sessionless work elsewhere. Standalone. |
| `/planning:design` | Design space | Explores types, contracts, module boundaries, and package topology through collaborative discussion rounds, producing capability-matrix / type-inventory / design-threads / topology artifacts; its `handoff` action delegates to `/planning:design-handoff`. |
| `/planning:design-handoff` | Design→plan gate | Gates a finished design for `/planning:plan` — a binary check that every `design-threads.md` thread is RESOLVED, directional, or TAGGED-DEFERRED — then packages the plan-ready summary and resume prompt, or FAILs and routes back to `/planning:design`. |
| `/planning:devils-advocate` | Adversarial review | Stress-tests plans via assumption extraction, evidence checks, failure scenarios, and operational-gotcha sweeps — every finding evidence-backed, never generic warnings. An `incumbent` mode turns the same lens on the status quo: an Alternatives Sweep that stress-tests keeping an incumbent tool/approach against alternatives (native > official > vetted ladder, coupling priced, KEEP / MIGRATE / RESEARCH verdict), exploring the incumbent first-hand in a fresh sub-agent. |
| `/planning:plan` | Implementation plan | Produces a structured plan (goal, approach, test strategy, blast radius, parallelism analysis, tagged unilateral decisions) with a mandatory fresh-context stress-test and a user approval gate, persisted to PLAN.md. |
| `/planning:setup` | Configuration | `check` inspects the topic-docs seam and standards index read-only; `apply` interviews the consumer and persists the tracked `.claude/topic-docs.yaml` concern file that governs where every pipeline skill writes its per-topic artifacts, and bootstraps the standards index (idempotent — re-run to reconfigure). |

The pipeline composes end-to-end — `wayfind` charts the fog upstream when an effort
is too big to hold at once, then `brainstorm → prd → interview → design →
design-handoff → plan` with `devils-advocate` attacking the plan before
approval — while `/domain-driven-design:curate-language` is invoked whenever
those workflows resolve vocabulary, when the `domain-driven-design` plugin is
installed; without it, resolved terms are recorded in the design artifacts
themselves. Every skill also works standalone.

## Works in any repo

- **Reads your conventions, assumes none.** Project rules, naming conventions,
  review checklists, domain-vocabulary files, and commit policy come from your own
  project's `CLAUDE.md` and rules; where none exist, the skills apply standard
  engineering defaults.
- **Graceful degrade.** Adjacent capabilities — codebase exploration and external
  research (`discovery`), test-design guidance (`tdd`), prototyping (`prototype`),
  session handoff (`session-flow`) — are invoked when installed and substituted
  with inline guidance when absent; no step blocks on a missing plugin.
- **Self-contained assets.** Templates and reference files ship inside the plugin;
  planning artifacts land per the topic-docs convention — contract documents in
  `<contract_dir>/<topic-slug>/` (default `docs/topics/`) on the task branch, working
  memory in the self-ignoring `<memory_dir>/<topic-slug>/` (default `.work/`) — never
  in plugin-internal paths.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install planning@melodic-software
```

## Configuration

Where artifacts land is governed by the marketplace-wide **topic-docs convention**
(`docs/conventions/topic-docs/` in this repository): contract documents (`PRD.md`,
`PLAN.md`, `design/`) go to `<contract_dir>/<topic-slug>/` (default `docs/topics/`) on
the task branch; working memory (checklists, baselines, scratch) goes to the
self-ignoring `<memory_dir>/<topic-slug>/` (default `.work/`). Run
`/planning:setup check` to inspect the effective values read-only, or
`/planning:setup apply` to interview and persist the tracked
concern file `.claude/topic-docs.yaml` (`contract_dir`, `memory_dir`,
`contract_tier: branch | local`); absent keys mean those documented defaults.

## License

MIT (SPDX-License-Identifier: MIT).
