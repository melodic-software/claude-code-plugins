# Skill Cheat Sheet

A scan-and-go "doing X → run this skill" map of every listed skill in this marketplace,
generated from each skill's SKILL.md frontmatter by `scripts/generate-cheatsheet.mjs`.
Do not hand-edit the generated block below — edit the source frontmatter and regenerate.

Grouping axis: this page groups skills by **sequence of use** — the session-flow workflow
stages you move through while working. The separate what-kind-of-plugin taxonomy axis is
owned by [docs/CATALOG-TAXONOMY.md](CATALOG-TAXONOMY.md).

<!-- cheatsheet:start -->

- [0. Contract](#0-contract)
- [1. Explore](#1-explore)
- [2. Research](#2-research)
- [3. Plan](#3-plan)
- [4. Implement](#4-implement)
- [5. Test](#5-test)
- [6. Review](#6-review)
- [7. Verify outcome](#7-verify-outcome)
- [8. Retrospective](#8-retrospective)
- [PR lifecycle (after step 7)](#pr-lifecycle-after-step-7)
- [Anytime / cross-cutting](#anytime--cross-cutting)
- [Session lifecycle](#session-lifecycle)
- [Operator cadence](#operator-cadence)

## 0. Contract

| Skill | Plugin | What it does |
| --- | --- | --- |
| [`/bug-report:write`](../plugins/bug-report/skills/write/SKILL.md) | `bug-report` | Turn an informal bug description into a structured 5-field report, read-only |
| [`/planning:audit-answers`](../plugins/planning/skills/audit-answers/SKILL.md) | `planning` | Adversarially validate interview answers with fresh-context agents |
| [`/planning:brainstorm`](../plugins/planning/skills/brainstorm/SKILL.md) | `planning` | Diverge into codebase-grounded candidate approaches before scoping |
| [`/planning:interview`](../plugins/planning/skills/interview/SKILL.md) | `planning` | Interview in frontier rounds until the task contract is locked |
| [`/planning:prd`](../plugins/planning/skills/prd/SKILL.md) | `planning` | Lock product intent — problem, users, success metrics — before planning |
| [`/planning:questionnaire`](../plugins/planning/skills/questionnaire/SKILL.md) | `planning` | Turn a decision someone else must answer into an async questionnaire |
| [`/planning:wayfind`](../plugins/planning/skills/wayfind/SKILL.md) | `planning` | Chart a too-big, foggy effort as a decision map worked one decision at a time |

## 1. Explore

| Skill | Plugin | What it does |
| --- | --- | --- |
| [`/discovery:blindspot`](../plugins/discovery/skills/blindspot/SKILL.md) | `discovery` | Surface your unknown-unknowns and sharpen the prompt before unfamiliar work |
| [`/discovery:explore`](../plugins/discovery/skills/explore/SKILL.md) | `discovery` | Explore code, history, tests, and config before changing anything |

## 2. Research

| Skill | Plugin | What it does |
| --- | --- | --- |
| [`/context7:lookup`](../plugins/context7/skills/lookup/SKILL.md) | `context7` | Look up current library docs, API references, and examples via Context7 |
| [`/discovery:research`](../plugins/discovery/skills/research/SKILL.md) | `discovery` | Multi-source external research with source tiers and a coverage ledger |
| [`/discovery:research-deep`](../plugins/discovery/skills/research-deep/SKILL.md) | `discovery` | Dispatch deep multi-topic research to the heaviest isolated tier |
| [`/dometrain:grounding`](../plugins/dometrain/skills/grounding/SKILL.md) | `dometrain` | Ground an approach in how a Dometrain course teaches it, with lesson links |
| [`/firecrawl:firecrawl`](../plugins/firecrawl/skills/firecrawl/SKILL.md) | `firecrawl` | Scrape, search, crawl, or parse web pages when WebFetch is blocked |

## 3. Plan

| Skill | Plugin | What it does |
| --- | --- | --- |
| [`/architecture:improve`](../plugins/architecture/skills/improve/SKILL.md) | `architecture` | Scan the codebase for shallow modules and friction, then design the chosen fix several ways |
| [`/domain-driven-design:curate-language`](../plugins/domain-driven-design/skills/curate-language/SKILL.md) | `domain-driven-design` | Maintain the domain glossary — resolve terms, record rejected synonyms |
| [`/event-storming:methodology`](../plugins/event-storming/skills/methodology/SKILL.md) | `event-storming` | EventStorming facilitation reference across all three formats |
| [`/event-storming:simulation`](../plugins/event-storming/skills/simulation/SKILL.md) | `event-storming` | Multi-persona agentic EventStorming workshop on Miro |
| [`/naming:name-it-better`](../plugins/naming/skills/name-it-better/SKILL.md) | `naming` | Generate and evaluate name candidates from blind fresh-context lenses |
| [`/planning:design`](../plugins/planning/skills/design/SKILL.md) | `planning` | Resolve types, contracts, and module boundaries before planning |
| [`/planning:design-handoff`](../plugins/planning/skills/design-handoff/SKILL.md) | `planning` | Gate a finished design and package it for planning |
| [`/planning:devils-advocate`](../plugins/planning/skills/devils-advocate/SKILL.md) | `planning` | Stress-test a plan or the incumbent approach adversarially |
| [`/planning:draft-goal-condition`](../plugins/planning/skills/draft-goal-condition/SKILL.md) | `planning` | Pick the right autonomy lever and craft a /goal completion condition |
| [`/planning:plan`](../plugins/planning/skills/plan/SKILL.md) | `planning` | Produce a structured implementation plan with an approval gate |
| [`/prototype:explore-directions`](../plugins/prototype/skills/explore-directions/SKILL.md) | `prototype` | Throwaway UI variations answering what should this look like |
| [`/prototype:pressure-test`](../plugins/prototype/skills/pressure-test/SKILL.md) | `prototype` | Throwaway terminal app pressure-testing logic or a data model |
| [`/work-items:decompose`](../plugins/work-items/skills/decompose/SKILL.md) | `work-items` | Break a plan into vertical-slice work items with dependencies |

## 4. Implement

| Skill | Plugin | What it does |
| --- | --- | --- |
| [`/debugging:debug`](../plugins/debugging/skills/debug/SKILL.md) | `debugging` | Diagnose broken behavior — reproduce, hypothesise, instrument, fix with regression test |
| [`/implementation:implement`](../plugins/implementation/skills/implement/SKILL.md) | `implementation` | Execute approved plans with TDD, incremental validation, and green commits |
| [`/implementation:implement-dispatch`](../plugins/implementation/skills/implement-dispatch/SKILL.md) | `implementation` | Orchestrate worker subagents to execute an approved plan |
| [`/source-control:commit`](../plugins/source-control/skills/commit/SKILL.md) | `source-control` | Commit with the resolved convention and surgical staging |

## 5. Test

| Skill | Plugin | What it does |
| --- | --- | --- |
| [`/playwright:playwright`](../plugins/playwright/skills/playwright/SKILL.md) | `playwright` | Live E2E browser automation with disk-written artifacts |
| [`/tdd:principles`](../plugins/tdd/skills/principles/SKILL.md) | `tdd` | Answer test design questions from authoritative TDD sources |
| [`/testing:diagnose`](../plugins/testing/skills/diagnose/SKILL.md) | `testing` | Root-cause failing tests — never retry blindly |
| [`/testing:plan`](../plugins/testing/skills/plan/SKILL.md) | `testing` | Classify changes by required test type and coverage gaps |
| [`/testing:run-e2e`](../plugins/testing/skills/run-e2e/SKILL.md) | `testing` | Start the app, drive real flows, capture evidence |
| [`/testing:write`](../plugins/testing/skills/write/SKILL.md) | `testing` | Write and place tests with TDD cadence across ecosystems |

## 6. Review

| Skill | Plugin | What it does |
| --- | --- | --- |
| [`/code-tidying:audit-comment-residue`](../plugins/code-tidying/skills/audit-comment-residue/SKILL.md) | `code-tidying` | Classify code comments for history narration and session-reference residue |
| [`/code-tidying:batch-simplify`](../plugins/code-tidying/skills/batch-simplify/SKILL.md) | `code-tidying` | Batch-run simplification across all recently changed files by ecosystem |
| [`/mcp-tools:audit`](../plugins/mcp-tools/skills/audit/SKILL.md) | `mcp-tools` | Audit MCP tool definitions against design quality criteria |
| [`/plugin-quality:audit`](../plugins/plugin-quality/skills/audit/SKILL.md) | `plugin-quality` | Behavioral audit of a plugin component ending in a maintainer work item |
| [`/review:fanout`](../plugins/review/skills/fanout/SKILL.md) | `review` | Fan review out across every reviewer surface into one ranked report |
| [`/review:quality-gate`](../plugins/review/skills/quality-gate/SKILL.md) | `review` | Single-lens review checkpoint routed to the matching reviewer |
| [`/skill-quality:check`](../plugins/skill-quality/skills/check/SKILL.md) | `skill-quality` | Static QA gate for skill frontmatter, caps, and evals |

## 7. Verify outcome

| Skill | Plugin | What it does |
| --- | --- | --- |
| [`/toolchain:check`](../plugins/toolchain/skills/check/SKILL.md) | `toolchain` | Build, test, and lint changed files across detected ecosystems |
| [`/toolchain:lint`](../plugins/toolchain/skills/lint/SKILL.md) | `toolchain` | Polyglot lint and format checks without a full build |
| [`/verification:confirm`](../plugins/verification/skills/confirm/SKILL.md) | `verification` | Prove the change achieved its intended outcome with evidence |
| [`/verification:measure`](../plugins/verification/skills/measure/SKILL.md) | `verification` | Verify an improvement claim against a pre-change baseline |

## 8. Retrospective

| Skill | Plugin | What it does |
| --- | --- | --- |
| [`/session-flow:retro`](../plugins/session-flow/skills/retro/SKILL.md) | `session-flow` | Structured session retrospective with codified learnings |
| [`/session-flow:running-retro`](../plugins/session-flow/skills/running-retro/SKILL.md) | `session-flow` | In-flight retro checkpoint appended to a running ledger |

## PR lifecycle (after step 7)

| Skill | Plugin | What it does |
| --- | --- | --- |
| [`/source-control:pull-request`](../plugins/source-control/skills/pull-request/SKILL.md) | `source-control` | Full PR lifecycle — prep, create, monitor CI, address reviews, merge |
| [`/source-control:resolve-conflicts`](../plugins/source-control/skills/resolve-conflicts/SKILL.md) | `source-control` | Resolve merge and rebase conflicts by recovering both sides' intent |

## Anytime / cross-cutting

| Skill | Plugin | What it does |
| --- | --- | --- |
| [`/adhd:clarify`](../plugins/adhd/skills/clarify/SKILL.md) | `adhd` | Reshape a dense, decision-heavy message into clear one-decision-at-a-time chunks, losing nothing |
| [`/adhd:shape`](../plugins/adhd/skills/shape/SKILL.md) | `adhd` | Set a standing action-first output posture — lead with the next action, cut preamble |
| [`/claude-config:audit`](../plugins/claude-config/skills/audit/SKILL.md) | `claude-config` | Audit settings, hooks, permissions, and MCP config for drift against current official docs |
| [`/claude-config:audit-automation-gaps`](../plugins/claude-config/skills/audit-automation-gaps/SKILL.md) | `claude-config` | Audit the repo's automation landscape for hook, MCP, skill, and subagent gaps worth adding |
| [`/claude-config:audit-instructions`](../plugins/claude-config/skills/audit-instructions/SKILL.md) | `claude-config` | Find instructions current models no longer need across CLAUDE.md, rules, and skill bodies |
| [`/claude-config:audit-pass`](../plugins/claude-config/skills/audit-pass/SKILL.md) | `claude-config` | Run one coordinated, resumable audit pass over a repo with a single human gate |
| [`/claude-config:audit-permission-grants`](../plugins/claude-config/skills/audit-permission-grants/SKILL.md) | `claude-config` | Audit permission grants for portability and auto-mode durability |
| [`/claude-memory:audit`](../plugins/claude-memory/skills/audit/SKILL.md) | `claude-memory` | Audit CLAUDE.md, rules, and auto-memory against the official-docs checklist |
| [`/claude-memory:stateless`](../plugins/claude-memory/skills/stateless/SKILL.md) | `claude-memory` | Inspect, disable, or purge Claude Code's per-repo auto memory |
| [`/claude-ops:changelog`](../plugins/claude-ops/skills/changelog/SKILL.md) | `claude-ops` | Ingest a Claude Code release changelog and integrate its changes into the repo |
| [`/claude-ops:known-issues`](../plugins/claude-ops/skills/known-issues/SKILL.md) | `claude-ops` | Look up and track known Claude product issues, health, and workarounds |
| [`/code-tidying:tidy`](../plugins/code-tidying/skills/tidy/SKILL.md) | `code-tidying` | Proactively hunt one lane for safe structural tidyings and ship a structure-only PR |
| [`/codebase-health:audit`](../plugins/codebase-health/skills/audit/SKILL.md) | `codebase-health` | Audit for drift between docs, config, code, and architecture via verified findings |
| [`/discipline:do-your-research`](../plugins/discipline/skills/do-your-research/SKILL.md) | `discipline` | Re-anchor research discipline, then audit and correct the current work |
| [`/discipline:do-your-research-deep`](../plugins/discipline/skills/do-your-research-deep/SKILL.md) | `discipline` | Verify every session claim against primary sources in a heavy fan-out |
| [`/discipline:follow-our-standards`](../plugins/discipline/skills/follow-our-standards/SKILL.md) | `discipline` | Re-anchor to org engineering standards and audit the work in flight |
| [`/discipline:mind-your-maxims`](../plugins/discipline/skills/mind-your-maxims/SKILL.md) | `discipline` | Re-anchor cooperative communication and audit recent responses for clarity |
| [`/discipline:pick-for-the-problem`](../plugins/discipline/skills/pick-for-the-problem/SKILL.md) | `discipline` | Re-derive a tool or approach choice from the problem, not habit |
| [`/discipline:point-dont-copy`](../plugins/discipline/skills/point-dont-copy/SKILL.md) | `discipline` | Audit for copied content and correct by pointing at the living source |
| [`/discipline:reason-dont-recite`](../plugins/discipline/skills/reason-dont-recite/SKILL.md) | `discipline` | Challenge decisions coasting on precedent, re-derive from first principles |
| [`/discipline:recheck-against-upstream`](../plugins/discipline/skills/recheck-against-upstream/SKILL.md) | `discipline` | Audit the surface in flight against current official upstream docs |
| [`/discipline:recheck-against-upstream-deep`](../plugins/discipline/skills/recheck-against-upstream-deep/SKILL.md) | `discipline` | Fan out doc-by-doc upstream conformance checks across a whole subsystem |
| [`/discipline:reuse-or-replace`](../plugins/discipline/skills/reuse-or-replace/SKILL.md) | `discipline` | Reuse the established way or openly replace it — never a silent second way |
| [`/discipline:script-the-deterministic-work`](../plugins/discipline/skills/script-the-deterministic-work/SKILL.md) | `discipline` | Script counting, diffing, and transforms instead of eyeballing them |
| [`/discipline:scrutinize-dont-coast`](../plugins/discipline/skills/scrutinize-dont-coast/SKILL.md) | `discipline` | Re-examine your own recent output through a fresh-context pass |
| [`/discipline:sweep-all`](../plugins/discipline/skills/sweep-all/SKILL.md) | `discipline` | Batch every discipline corrector into one audited re-anchor pass |
| [`/discipline:tighten-your-output`](../plugins/discipline/skills/tighten-your-output/SKILL.md) | `discipline` | Tighten prose and code — fewer words, no semantic loss |
| [`/discipline:use-your-skills`](../plugins/discipline/skills/use-your-skills/SKILL.md) | `discipline` | Map the task to available skills and invoke them instead of reinventing |
| [`/disk-hygiene:clean`](../plugins/disk-hygiene/skills/clean/SKILL.md) | `disk-hygiene` | Audit a directory tree for stale leftovers and remove validated paths |
| [`/docs-hygiene:audit-derivability`](../plugins/docs-hygiene/skills/audit-derivability/SKILL.md) | `docs-hygiene` | Judge whether a doc earns its existence or should become a pointer |
| [`/docs-hygiene:audit-encapsulation`](../plugins/docs-hygiene/skills/audit-encapsulation/SKILL.md) | `docs-hygiene` | Find external citations reaching into a skill's private surfaces |
| [`/docs-hygiene:audit-noise`](../plugins/docs-hygiene/skills/audit-noise/SKILL.md) | `docs-hygiene` | Classify markdown for stale citations, ghost refs, and meta-commentary |
| [`/docs-hygiene:compress`](../plugins/docs-hygiene/skills/compress/SKILL.md) | `docs-hygiene` | Tighten markdown by dropping flavor while preserving every directive |
| [`/docs-hygiene:extract-ssot`](../plugins/docs-hygiene/skills/extract-ssot/SKILL.md) | `docs-hygiene` | Deduplicate repeated prose into one named source of truth |
| [`/docs-hygiene:rename-references`](../plugins/docs-hygiene/skills/rename-references/SKILL.md) | `docs-hygiene` | Sweep stale references after renames, including forms grep misses |
| [`/education:explain`](../plugins/education/skills/explain/SKILL.md) | `education` | Explain any concept or the last response in genuinely plain words |
| [`/education:quiz-me`](../plugins/education/skills/quiz-me/SKILL.md) | `education` | Generate a post-change report with a quiz verifying you absorbed the work |
| [`/education:teach`](../plugins/education/skills/teach/SKILL.md) | `education` | Multi-session learning coach for general topics or repo-grounded concepts |
| [`/github:advise`](../plugins/github/skills/advise/SKILL.md) | `github` | Design and set up GitHub settings and admin areas grounded in live gh state |
| [`/github:audit`](../plugins/github/skills/audit/SKILL.md) | `github` | Read-only audit of GitHub org and repo settings, drift, and cost signals |
| [`/playbooks:boris`](../plugins/playbooks/skills/boris/SKILL.md) | `playbooks` | Boris Cherny's Claude Code workflow tips across 115 sections |
| [`/playbooks:fable-5`](../plugins/playbooks/skills/fable-5/SKILL.md) | `playbooks` | Fable 5's operating doctrine loaded as standing session instructions |
| [`/playbooks:skill-authoring`](../plugins/playbooks/skills/skill-authoring/SKILL.md) | `playbooks` | Anthropic's internal skill-authoring playbook and patterns |
| [`/repo-hygiene:clean`](../plugins/repo-hygiene/skills/clean/SKILL.md) | `repo-hygiene` | Clean caches, build artifacts, stale branches, and stashes per repo |
| [`/session-flow:workflow`](../plugins/session-flow/skills/workflow/SKILL.md) | `session-flow` | Navigate the staged dev workflow and suggest the next stage |
| [`/visualization:visualize`](../plugins/visualization/skills/visualize/SKILL.md) | `visualization` | Pick the best visual form for what is in the conversation and render it |
| [`/work-items:scan-todos`](../plugins/work-items/skills/scan-todos/SKILL.md) | `work-items` | Sweep source comments for TODO and FIXME markers, resolve or file each |
| [`/work-items:track`](../plugins/work-items/skills/track/SKILL.md) | `work-items` | Backlog CRUD through the bound tracker — add, list, close, stats |
| [`/work-items:triage`](../plugins/work-items/skills/triage/SKILL.md) | `work-items` | Evaluate raw intake through the verified-to-eligible state machine |
| [`/work-items:work`](../plugins/work-items/skills/work/SKILL.md) | `work-items` | Auto-select one work item and execute it end-to-end |

## Session lifecycle

| Skill | Plugin | What it does |
| --- | --- | --- |
| [`/session-flow:clean-stop`](../plugins/session-flow/skills/clean-stop/SKILL.md) | `session-flow` | Make everything durable before the machine goes away |
| [`/session-flow:continue-in-background`](../plugins/session-flow/skills/continue-in-background/SKILL.md) | `session-flow` | Delegate the task to a fresh background agent now |
| [`/session-flow:find-handoff`](../plugins/session-flow/skills/find-handoff/SKILL.md) | `session-flow` | Recover a lost handoff or resume prompt after /clear |
| [`/session-flow:handoff`](../plugins/session-flow/skills/handoff/SKILL.md) | `session-flow` | Write a mid-session save-point for clear-and-resume |
| [`/session-flow:keep-going`](../plugins/session-flow/skills/keep-going/SKILL.md) | `session-flow` | Recover after an interruption and continue where work stood |
| [`/session-flow:orchestrate`](../plugins/session-flow/skills/orchestrate/SKILL.md) | `session-flow` | Arm the session with proactive-orchestration imperatives |
| [`/session-flow:orient`](../plugins/session-flow/skills/orient/SKILL.md) | `session-flow` | Read-only situation report from durable and off-thread state |
| [`/session-flow:reanchor`](../plugins/session-flow/skills/reanchor/SKILL.md) | `session-flow` | Verify working assumptions are still true before building on them |
| [`/session-flow:reconcile`](../plugins/session-flow/skills/reconcile/SKILL.md) | `session-flow` | Retire finished off-thread work and square the task ledger |
| [`/source-control:worktree`](../plugins/source-control/skills/worktree/SKILL.md) | `source-control` | Create, inspect, and clean git worktrees for parallel sessions |

## Operator cadence

| Skill | Plugin | Cadence | What it does |
| --- | --- | --- | --- |
| [`/claude-ops:lanes`](../plugins/claude-ops/skills/lanes/SKILL.md) | `claude-ops` | daily | Start, restart, stop, and check loop lanes as named background sessions |
| [`/claude-ops:morning-brief`](../plugins/claude-ops/skills/morning-brief/SKILL.md) | `claude-ops` | daily | Print the operator's read-only morning view — queues, merge-ready PRs, parked decisions |
| [`/claude-ops:observability`](../plugins/claude-ops/skills/observability/SKILL.md) | `claude-ops` | weekly | Report on locally captured telemetry — token burn, cost, hook latency, trends |
| [`/claude-ops:plugins`](../plugins/claude-ops/skills/plugins/SKILL.md) | `claude-ops` | weekly | Bring the machine's plugin fleet current — refresh, update, install per policy |
| [`/repo-fleet-hygiene:audit`](../plugins/repo-fleet-hygiene/skills/audit/SKILL.md) | `repo-fleet-hygiene` | weekly | Audit git and GitHub hygiene across all local repositories, read-only |
| [`/source-control:babysit-loop`](../plugins/source-control/skills/babysit-loop/SKILL.md) | `source-control` | continuous | Run one repo's PR queue as a standing merge lane |
| [`/source-control:babysit-prs`](../plugins/source-control/skills/babysit-prs/SKILL.md) | `source-control` | continuous | Tiered fleet pass advancing your open PRs |
| [`/work-items:attend-queue`](../plugins/work-items/skills/attend-queue/SKILL.md) | `work-items` | daily | Drive escalated and untriaged items to resolution in one view |
| [`/work-items:work-loop`](../plugins/work-items/skills/work-loop/SKILL.md) | `work-items` | continuous | Drain the backlog as a self-paced autonomous loop |

<!-- cheatsheet:end -->
