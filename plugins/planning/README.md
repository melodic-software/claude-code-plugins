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
| `/planning:interview` | Engineering contract | Locks a task contract (goal, constraints, acceptance criteria, named assumptions) into a PLAN.md Brief — synthesizing when intent is clear, running depth-first Q&A when it isn't, or interviewing relentlessly on request. |
| `/planning:design` | Design space | Explores types, contracts, module boundaries, and package topology through collaborative discussion rounds, producing capability-matrix / type-inventory / design-threads / topology artifacts; its `handoff` action delegates to `/planning:design-handoff`. |
| `/planning:design-handoff` | Design→plan gate | Gates a finished design for `/planning:architect` — a binary check that every `design-threads.md` thread is RESOLVED, directional, or TAGGED-DEFERRED — then packages the architect-ready summary and resume prompt, or FAILs and routes back to `/planning:design`. |
| `/planning:devils-advocate` | Adversarial review | Stress-tests plans via assumption extraction, evidence checks, failure scenarios, and operational-gotcha sweeps — every finding evidence-backed, never generic warnings. |
| `/planning:architect` | Implementation plan | Produces a structured plan (goal, approach, test strategy, blast radius, parallelism analysis, tagged unilateral decisions) with a mandatory fresh-context stress-test and a user approval gate, persisted to PLAN.md. |
| `/planning:setup` | Configuration | Interviews the consumer and persists the `notes_dir` config that governs where every pipeline skill writes its per-topic artifacts (idempotent — re-run to reconfigure). |

The pipeline composes end-to-end — `wayfind` charts the fog upstream when an effort
is too big to hold at once, then `brainstorm → prd → interview → design →
design-handoff → architect` with `devils-advocate` attacking the plan before
approval — but every skill also works standalone.

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
  planning artifacts are written to your configured notes directory, never to
  plugin-internal paths.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install planning@melodic-software
```

## Configuration

One option, prompted at enable time (or set any time with `/planning:setup`):

| Option | Type | Default | Purpose |
|---|---|---|---|
| `notes_dir` | string | `.claude/notes` | Project-relative directory where planning artifacts (`PRD.md`, `PLAN.md`, design artifacts, checklists) are written, one subdirectory per topic. A working-notes convention declared in your own project's `CLAUDE.md` or rules takes precedence. |

## License

MIT (SPDX-License-Identifier: MIT). See the `LICENSE` file at the root of the
melodic-software/claude-code-plugins repository.
