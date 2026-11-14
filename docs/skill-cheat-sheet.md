# Skill Cheat Sheet

A scan-and-go "doing X → run this skill" map of every listed skill in this marketplace,
generated from each skill's SKILL.md frontmatter by `scripts/generate-cheatsheet.mjs`.
Each row's **Actions** are the action words of the skill's `argument-hint` (the first argument's
choices), and its **Next** lists the skills its `## Next` section names, in order; either is empty
when the skill has none. Do not hand-edit the generated block below. Edit the source SKILL.md
and regenerate.

Grouping axis: this page groups skills by **sequence of use**, the session-flow workflow
stages you move through while working. The separate what-kind-of-plugin taxonomy axis is
owned by [docs/catalog-taxonomy.md](catalog-taxonomy.md).

## Start from your problem

| I want to | Start with |
| --- | --- |
| Understand code before changing it | [`/discovery:explore`](../plugins/discovery/skills/explore/SKILL.md) |
| Find out why something was built this way | [`/discovery:trace-intent`](../plugins/discovery/skills/trace-intent/SKILL.md) |
| Answer a question from outside sources | [`/discovery:research`](../plugins/discovery/skills/research/SKILL.md) |
| Pin down a vague task before building it | [`/planning:interview`](../plugins/planning/skills/interview/SKILL.md) |
| Make a code change | [`/implementation:implement`](../plugins/implementation/skills/implement/SKILL.md) |
| Find the cause of a bug or failure | [`/debugging:debug`](../plugins/debugging/skills/debug/SKILL.md) |
| Fix a failing test | [`/testing:diagnose`](../plugins/testing/skills/diagnose/SKILL.md) |
| Get my change reviewed | [`/review:quality-gate`](../plugins/review/skills/quality-gate/SKILL.md) |
| Prove my change worked | [`/verification:confirm`](../plugins/verification/skills/confirm/SKILL.md) |
| Open, watch or merge a pull request | [`/source-control:pull-request`](../plugins/source-control/skills/pull-request/SKILL.md) |
| Work the next item in the backlog | [`/work-items:work`](../plugins/work-items/skills/work/SKILL.md) |
| Pick up after an interruption | [`/session-flow:keep-going`](../plugins/session-flow/skills/keep-going/SKILL.md) |
| See which skills fit right now | [`/session-flow:recommend-skills`](../plugins/session-flow/skills/recommend-skills/SKILL.md) |

<!-- BEGIN GENERATED: cheatsheet. Run node scripts/generate-cheatsheet.mjs -->

- [1. Interview](#1-interview)
- [2. Explore](#2-explore)
- [3. Research](#3-research)
- [4. PRD](#4-prd)
- [5. Design](#5-design)
- [6. Plan](#6-plan)
- [7. Decompose](#7-decompose)
- [8. Implement](#8-implement)
- [9. Test](#9-test)
- [10. Review](#10-review)
- [11. Verify outcome](#11-verify-outcome)
- [12. Retrospective](#12-retrospective)
- [Ship: PR lifecycle (after stage 11)](#ship-pr-lifecycle-after-stage-11)
- [Anytime / cross-cutting](#anytime--cross-cutting)
- [Session lifecycle](#session-lifecycle)
- [Operator cadence](#operator-cadence)

## 1. Interview

| Skill | Plugin | What it does | Actions | Next |
| --- | --- | --- | --- | --- |
| [`/bugs:write`](../plugins/bugs/skills/write/SKILL.md) | `bugs` | Turn an informal bug description into a structured 5-field report, read-only |  | `/work-items:track`, `/debugging:debug`, `/implementation:implement` |
| [`/planning:audit-answers`](../plugins/planning/skills/audit-answers/SKILL.md) | `planning` | Adversarially validate interview answers with fresh-context agents |  | `/planning:design` |
| [`/planning:interview`](../plugins/planning/skills/interview/SKILL.md) | `planning` | Interview in frontier rounds until the task contract is locked | `me`, `lock`, `scope`, `restate`, `share`, `document`, `product` | `/planning:design`, `/planning:audit-answers`, `/planning:wayfind`, `/session-flow:workflow` |
| [`/planning:wayfind`](../plugins/planning/skills/wayfind/SKILL.md) | `planning` | Chart a too-big, foggy effort as a decision map worked one decision at a time | `chart`, `work` | `/planning:wayfind`, `/planning:interview`, `/planning:plan`, `/work-items:decompose`, `/planning:prd` |

## 2. Explore

| Skill | Plugin | What it does | Actions | Next |
| --- | --- | --- | --- | --- |
| [`/architecture:map-components`](../plugins/architecture/skills/map-components/SKILL.md) | `architecture` | Chart the modules inside one deployable as a C4 component view |  | `/architecture:improve`, `/planning:design`, `/architecture:map-landscape`, `/architecture:record-decision` |
| [`/architecture:map-containers`](../plugins/architecture/skills/map-containers/SKILL.md) | `architecture` | Chart deployables, the stores they bind, and contained modules |  | `/architecture:map-components`, `/architecture:map-flow`, `/architecture:map-landscape`, `/planning:design`, `/architecture:record-decision` |
| [`/architecture:map-context`](../plugins/architecture/skills/map-context/SKILL.md) | `architecture` | Chart one software system's C4 system context from tracked configuration |  | `/architecture:map-landscape`, `/architecture:record-decision`, `/architecture:improve`, `/planning:design` |
| [`/architecture:map-data`](../plugins/architecture/skills/map-data/SKILL.md) | `architecture` | Draw an ERD from a committed schema, offline |  | `/architecture:record-decision`, `/planning:design`, `/architecture:map-landscape` |
| [`/architecture:map-dependencies`](../plugins/architecture/skills/map-dependencies/SKILL.md) | `architecture` | Cite project and package edges from build manifests |  | `/architecture:map-components` |
| [`/architecture:map-deployment`](../plugins/architecture/skills/map-deployment/SKILL.md) | `architecture` | Chart IaC deployment topology per environment, with a diff |  | `/architecture:record-decision`, `/planning:design`, `/architecture:map-landscape` |
| [`/architecture:map-events`](../plugins/architecture/skills/map-events/SKILL.md) | `architecture` | Chart publishers, consumers, and orphan messages |  | `/architecture:map-flow`, `/architecture:map-containers`, `/architecture:record-decision`, `/planning:design` |
| [`/architecture:map-flow`](../plugins/architecture/skills/map-flow/SKILL.md) | `architecture` | Trace one C# entry point into a sequence diagram with a citation on every hop |  | `/architecture:map-events`, `/architecture:record-decision`, `/planning:design` |
| [`/architecture:map-landscape`](../plugins/architecture/skills/map-landscape/SKILL.md) | `architecture` | Chart a repository and the systems it references as a C4 system landscape and portfolio table |  | `/architecture:map-components`, `/architecture:improve`, `/discovery:explore`, `/architecture:record-decision` |
| [`/debugging:analyze-profile`](../plugins/debugging/skills/analyze-profile/SKILL.md) | `debugging` | Read a profile, trace or heap snapshot down to a file:line cause |  | `/debugging:debug`, `/performance:goal` |
| [`/discovery:blindspot`](../plugins/discovery/skills/blindspot/SKILL.md) | `discovery` | Surface your unknown-unknowns and sharpen the prompt before unfamiliar work |  | `/discovery:explore`, `/planning:interview`, `/session-flow:workflow` |
| [`/discovery:explore`](../plugins/discovery/skills/explore/SKILL.md) | `discovery` | Explore code, history, tests, and config before changing anything |  | `/discovery:research`, `/planning:interview`, `/planning:design`, `/session-flow:workflow` |
| [`/discovery:trace-intent`](../plugins/discovery/skills/trace-intent/SKILL.md) | `discovery` | Reconstruct why a thing was built this way, from evidence outside the code |  | `/planning:design`, `/planning:plan` |
| [`/performance:go-faster`](../plugins/performance/skills/go-faster/SKILL.md) | `performance` | Whole-process speed sweep with evidenced, ranked findings and adopt-now speedups |  | `/performance:goal`, `/overengineering:audit`, `/harness-ops:audit-performance`, `/performance:target` |
| [`/performance:target`](../plugins/performance/skills/target/SKILL.md) | `performance` | Rank optimization candidates by evidence quality, not suspicion |  | `/performance:goal`, `/performance:go-faster` |

## 3. Research

| Skill | Plugin | What it does | Actions | Next |
| --- | --- | --- | --- | --- |
| [`/context7:lookup`](../plugins/context7/skills/lookup/SKILL.md) | `context7` | Look up current library docs, API references, and examples via Context7 | `lookup`, `update` |  |
| [`/discovery:read-docs`](../plugins/discovery/skills/read-docs/SKILL.md) | `discovery` | Read an upstream docs page through the shared lookup and cache |  | `/discovery:research`, `/planning:plan` |
| [`/discovery:research`](../plugins/discovery/skills/research/SKILL.md) | `discovery` | Multi-source external research with source tiers and a coverage ledger |  | `/planning:interview`, `/planning:design`, `/session-flow:workflow` |
| [`/dometrain:grounding`](../plugins/dometrain/skills/grounding/SKILL.md) | `dometrain` | Ground an approach in how a Dometrain course teaches it, with lesson links |  |  |
| [`/firecrawl:firecrawl`](../plugins/firecrawl/skills/firecrawl/SKILL.md) | `firecrawl` | Scrape, search, crawl, or parse web pages when WebFetch is blocked | `scrape`, `search`, `crawl`, `map`, `parse`, `interact`, `agent`, `monitor`, `developer`, `research`, `doctor` |  |

## 4. PRD

| Skill | Plugin | What it does | Actions | Next |
| --- | --- | --- | --- | --- |
| [`/planning:brainstorm`](../plugins/planning/skills/brainstorm/SKILL.md) | `planning` | Diverge into codebase-grounded candidate approaches before scoping |  | `/planning:interview`, `/planning:prd`, `/planning:design`, `/session-flow:workflow` |
| [`/planning:prd`](../plugins/planning/skills/prd/SKILL.md) | `planning` | Lock product intent. Problem, users, success metrics. Before planning |  | `/planning:interview`, `/planning:design`, `/work-items:track`, `/session-flow:workflow` |

## 5. Design

| Skill | Plugin | What it does | Actions | Next |
| --- | --- | --- | --- | --- |
| [`/planning:design`](../plugins/planning/skills/design/SKILL.md) | `planning` | Resolve types, contracts, and module boundaries before planning | `library`, `module`, `data`, `integration`, `system` | `/planning:plan`, `/planning:design-handoff`, `/user-interface:design` |
| [`/planning:design-handoff`](../plugins/planning/skills/design-handoff/SKILL.md) | `planning` | Gate a finished design and package it for planning |  | `/planning:plan`, `/planning:design` |
| [`/user-experience:structure`](../plugins/user-experience/skills/structure/SKILL.md) | `user-experience` | Shape user flows, information architecture and content structure, evidence-labeled |  | `/user-interface:design` |
| [`/user-interface:design`](../plugins/user-interface/skills/design/SKILL.md) | `user-interface` | Design interfaces from the project's system and installed tools; terminal guidance built in |  | `/prototype:explore-directions`, `/user-interface:write-css`, `/user-interface:write-animation`, `/user-interface:audit` |

## 6. Plan

| Skill | Plugin | What it does | Actions | Next |
| --- | --- | --- | --- | --- |
| [`/architecture:improve`](../plugins/architecture/skills/improve/SKILL.md) | `architecture` | Scan the codebase for shallow modules or boundary crossings, then design or hand on the chosen fix | `deepening`, `boundaries`, `conventions` | `/planning:plan`, `/coupling:reduce`, `/corrections:codify`, `/architecture:improve` |
| [`/domain-driven-design:ubiquitous-language`](../plugins/domain-driven-design/skills/ubiquitous-language/SKILL.md) | `domain-driven-design` | Find, read, seed, maintain and check the domain glossary | `locate`, `lookup`, `seed`, `curate`, `audit` | `/planning:plan` |
| [`/event-storming:methodology`](../plugins/event-storming/skills/methodology/SKILL.md) | `event-storming` | EventStorming facilitation reference across all three formats |  | `/event-storming:simulation`, `/planning:design` |
| [`/event-storming:simulation`](../plugins/event-storming/skills/simulation/SKILL.md) | `event-storming` | Multi-persona agentic EventStorming workshop on Miro |  | `/domain-driven-design:ubiquitous-language`, `/planning:design` |
| [`/naming:name-it-better`](../plugins/naming/skills/name-it-better/SKILL.md) | `naming` | Generate and evaluate name candidates from blind fresh-context lenses |  |  |
| [`/performance:goal`](../plugins/performance/skills/goal/SKILL.md) | `performance` | Build a goal with realistic and ideal targets plus a computed floor |  | `/performance:snapshot` |
| [`/planning:devils-advocate`](../plugins/planning/skills/devils-advocate/SKILL.md) | `planning` | Stress-test a plan or the incumbent approach adversarially | `deep`, `shallow` | `/planning:plan` |
| [`/planning:draft-goal-condition`](../plugins/planning/skills/draft-goal-condition/SKILL.md) | `planning` | Pick the right autonomy lever and craft a /goal completion condition |  | `/implementation:implement`, `/session-flow:continue-in-background`, `/work-items:decompose`, `/planning:interview` |
| [`/planning:plan`](../plugins/planning/skills/plan/SKILL.md) | `planning` | Produce a structured implementation plan with an approval gate | `review`, `close-out` | `/implementation:implement`, `/implementation:implement-dispatch`, `/work-items:decompose` |
| [`/prototype:explore-directions`](../plugins/prototype/skills/explore-directions/SKILL.md) | `prototype` | Throwaway UI variations answering what should this look like | `vary`, `combine`, `controls` | `/planning:design`, `/planning:plan`, `/prototype:pressure-test`, `/prototype:build-generator` |
| [`/prototype:pressure-test`](../plugins/prototype/skills/pressure-test/SKILL.md) | `prototype` | Throwaway terminal app or shareable HTML demo pressure-testing logic or a data model |  | `/planning:design`, `/planning:plan` |

## 7. Decompose

| Skill | Plugin | What it does | Actions | Next |
| --- | --- | --- | --- | --- |
| [`/work-items:decompose`](../plugins/work-items/skills/decompose/SKILL.md) | `work-items` | Break a plan into vertical-slice work items with dependencies |  | `/work-items:work`, `/work-items:ship` |

## 8. Implement

| Skill | Plugin | What it does | Actions | Next |
| --- | --- | --- | --- | --- |
| [`/animation:learn-style`](../plugins/animation/skills/learn-style/SKILL.md) | `animation` | Measure a traced clip into a style pack and check new scenes against it |  | `/animation:produce` |
| [`/animation:produce`](../plugins/animation/skills/produce/SKILL.md) | `animation` | Brief, boards, approval gate, shots, render, and pack review |  | `/animation:learn-style` |
| [`/animation:rotoscope`](../plugins/animation/skills/rotoscope/SKILL.md) | `animation` | Trace, render, measure and fit a 1:1 replica of a reference animation |  | `/animation:learn-style` |
| [`/debugging:debug`](../plugins/debugging/skills/debug/SKILL.md) | `debugging` | Diagnose broken behavior. Reproduce, hypothesize, instrument, fix with regression test |  | `/verification:confirm`, `/review:quality-gate`, `/implementation:implement`, `/debugging:analyze-profile`, `/planning:interview`, `/bugs:write`, `/session-flow:workflow` |
| [`/developer-experience:build-cli`](../plugins/developer-experience/skills/build-cli/SKILL.md) | `developer-experience` | Build, extend, port or review a team's command-line tools against the CLI contract |  | `/developer-experience:audit-tools`, `/review:quality-gate` |
| [`/explainer-video:produce`](../plugins/explainer-video/skills/produce/SKILL.md) | `explainer-video` | Script, narrate, render and check a ManimCE explainer video, frames judged in a fresh context |  | `/harness-ops:prerequisites`, `/source-control:pull-request` |
| [`/implementation:implement`](../plugins/implementation/skills/implement/SKILL.md) | `implementation` | Execute approved plans with TDD, incremental validation, and green commits | `feature`, `fix`, `refactor`, `replace`, `config` | `/testing:plan`, `/testing:audit`, `/testing:run-e2e`, `/review:quality-gate` |
| [`/implementation:implement-dispatch`](../plugins/implementation/skills/implement-dispatch/SKILL.md) | `implementation` | Orchestrate worker subagents to execute an approved plan |  | `/testing:plan`, `/testing:audit`, `/testing:run-e2e`, `/review:quality-gate` |
| [`/instruction-placement:migrate`](../plugins/instruction-placement/skills/migrate/SKILL.md) | `instruction-placement` | Move a repository's instruction content to AGENTS.md behind an operator gate | `plan`, `apply`, `cutover-check`, `remove-shims` | `/instruction-placement:check` |
| [`/instruction-placement:realign`](../plugins/instruction-placement/skills/realign/SKILL.md) | `instruction-placement` | Apply accepted placement findings behind a per-item human gate |  |  |
| [`/overengineering:realign`](../plugins/overengineering/skills/realign/SKILL.md) | `overengineering` | Execute accepted audit findings down the rollback ladder behind a per-item human gate |  | `/verification:confirm` |
| [`/performance:climb`](../plugins/performance/skills/climb/SKILL.md) | `performance` | Keep or revert one measured change at a time until the goal is met |  | `/performance:verify` |
| [`/pixel-art:animate`](../plugins/pixel-art/skills/animate/SKILL.md) | `pixel-art` | Author, render, and review pixel-art animation cycles and sprite sheets |  | `/pixel-art:scene` |
| [`/pixel-art:scene`](../plugins/pixel-art/skills/scene/SKILL.md) | `pixel-art` | Author, render, and review a self-contained HTML pixel-art scene |  | `/pixel-art:animate` |
| [`/pixel-art:sprite`](../plugins/pixel-art/skills/sprite/SKILL.md) | `pixel-art` | Author, render, and review a static pixel-art sprite |  | `/pixel-art:animate` |
| [`/pixel-art:tileset`](../plugins/pixel-art/skills/tileset/SKILL.md) | `pixel-art` | Author, render, and review an engine tileset or parallax |  | `/pixel-art:scene` |
| [`/pixel-art:ui`](../plugins/pixel-art/skills/ui/SKILL.md) | `pixel-art` | Author, render, and review pixel-art UI skins, icons, and fonts |  | `/pixel-art:scene` |
| [`/pixel-art:vfx`](../plugins/pixel-art/skills/vfx/SKILL.md) | `pixel-art` | Author, render, and review pixel-art effects and animation cells |  | `/pixel-art:scene` |
| [`/prototype:build-generator`](../plugins/prototype/skills/build-generator/SKILL.md) | `prototype` | Throwaway generating tool the person tunes, whose saved output goes into the project | `save-output`, `add-controls`, `export` | `/verification:confirm` |
| [`/retro-audio:music`](../plugins/retro-audio/skills/music/SKILL.md) | `retro-audio` | Render a short chiptune score to a WAV file |  | `/pixel-art:scene` |
| [`/retro-audio:sfx`](../plugins/retro-audio/skills/sfx/SKILL.md) | `retro-audio` | Render one retro sound effect to a WAV file |  | `/retro-audio:music` |
| [`/source-control:commit`](../plugins/source-control/skills/commit/SKILL.md) | `source-control` | Commit with the resolved convention and surgical staging |  | `/source-control:pull-request` |
| [`/speech:narrate`](../plugins/speech/skills/narrate/SKILL.md) | `speech` | Script in, narration.wav and words.json out (kokoro local; elevenlabs optional, third-party) |  | `/harness-ops:prerequisites` |
| [`/user-interface:write-animation`](../plugins/user-interface/skills/write-animation/SKILL.md) | `user-interface` | Decide whether an element should animate, then write it in the project's stack |  | `/user-interface:audit` |
| [`/user-interface:write-css`](../plugins/user-interface/skills/write-css/SKILL.md) | `user-interface` | Write or review CSS after discovering the project's stack, tokens, targets and conventions |  | `/playwright:playwright`, `/user-interface:setup` |

## 9. Test

| Skill | Plugin | What it does | Actions | Next |
| --- | --- | --- | --- | --- |
| [`/app-control:drive`](../plugins/app-control/skills/drive/SKILL.md) | `app-control` | Run the app, drive it, record evidence, never judge | `ready`, `capture`, `cleanup`, `affected` | `/verification:confirm`, `/debugging:analyze-profile` |
| [`/app-control:map`](../plugins/app-control/skills/map/SKILL.md) | `app-control` | Generate, prove and keep current a control skill /app-control:drive runs | `create`, `check`, `refresh` | `/app-control:drive`, `/app-control:map` |
| [`/evals:design`](../plugins/evals/skills/design/SKILL.md) | `evals` | Interview for success criteria and scaffold an eval suite in the consumer repo | `app`, `skill`, `plugin` | `/evals:validate`, `/evals:plugin-eval` |
| [`/evals:methodology`](../plugins/evals/skills/methodology/SKILL.md) | `evals` | Answer LLM-evaluation design questions from Anthropic's official guidance |  | `/evals:design`, `/evals:plugin-eval` |
| [`/evals:plugin-eval`](../plugins/evals/skills/plugin-eval/SKILL.md) | `evals` | Preflight, price, run, and read a plugin eval suite around the CLI | `preflight`, `validate`, `run`, `read`, `ci`, `init` | `/evals:validate`, `/harness-config:unhobble`, `/evals:design` |
| [`/evals:validate`](../plugins/evals/skills/validate/SKILL.md) | `evals` | Static FAIL/WARN check of an eval suite's cases and graders, with no model call |  | `/evals:plugin-eval` |
| [`/mutation-testing:audit`](../plugins/mutation-testing/skills/audit/SKILL.md) | `mutation-testing` | Report surviving mutants on the diff or with --exercised, restoration verified, survivors triaged |  | `/testing:write`, `/mutation-testing:principles`, `/testing:test-value` |
| [`/mutation-testing:principles`](../plugins/mutation-testing/skills/principles/SKILL.md) | `mutation-testing` | Answer mutation-testing questions from the primary literature |  | `/mutation-testing:audit`, `/testing:write` |
| [`/playwright:playwright`](../plugins/playwright/skills/playwright/SKILL.md) | `playwright` | Live E2E browser automation with disk-written artifacts |  | `/source-control:pull-request`, `/verification:confirm`, `/playwright:demo-video` |
| [`/tdd:principles`](../plugins/tdd/skills/principles/SKILL.md) | `tdd` | Answer test design questions from authoritative TDD sources |  | `/testing:write` |
| [`/testing:audit`](../plugins/testing/skills/audit/SKILL.md) | `testing` | Detect tests that cannot fail. Report, gate, or persist |  | `/testing:write`, `/testing:cleanup`, `/review:fanout`, `/review:quality-gate` |
| [`/testing:check-visual-parity`](../plugins/testing/skills/check-visual-parity/SKILL.md) | `testing` | Baseline screenshots before a change, pixel counts against them after | `baseline`, `compare` | `/implementation:implement`, `/testing:run-e2e` |
| [`/testing:cleanup`](../plugins/testing/skills/cleanup/SKILL.md) | `testing` | Rewrite, quarantine or delete low-value tests behind a mutation gate, or delete cannot-fail ones |  | `/source-control:pull-request`, `/code-tidying:audit-dead-code` |
| [`/testing:diagnose`](../plugins/testing/skills/diagnose/SKILL.md) | `testing` | Root-cause failing tests, never retry blindly |  | `/verification:confirm`, `/testing:write` |
| [`/testing:plan`](../plugins/testing/skills/plan/SKILL.md) | `testing` | Classify changes by required test type and coverage gaps |  | `/testing:write` |
| [`/testing:run-e2e`](../plugins/testing/skills/run-e2e/SKILL.md) | `testing` | Start the app, drive real flows, capture evidence |  | `/review:quality-gate`, `/verification:confirm`, `/testing:diagnose` |
| [`/testing:test-value`](../plugins/testing/skills/test-value/SKILL.md) | `testing` | Where expected values come from and which tests earn their keep |  | `/testing:audit`, `/testing:cleanup` |
| [`/testing:write`](../plugins/testing/skills/write/SKILL.md) | `testing` | Write and place tests with TDD cadence across ecosystems |  | `/testing:audit` |

## 10. Review

| Skill | Plugin | What it does | Actions | Next |
| --- | --- | --- | --- | --- |
| [`/code-tidying:audit-comment-residue`](../plugins/code-tidying/skills/audit-comment-residue/SKILL.md) | `code-tidying` | Classify code comments for history narration and session-reference residue |  | `/code-tidying:remove-comments`, `/code-tidying:tidy`, `/debugging:debug`, `/implementation:implement` |
| [`/code-tidying:batch-simplify`](../plugins/code-tidying/skills/batch-simplify/SKILL.md) | `code-tidying` | Batch-run simplification across changed files, or a whole repository, by ecosystem | `time-window`, `branch`, `repo` | `/verification:confirm` |
| [`/code-tidying:remove-comments`](../plugins/code-tidying/skills/remove-comments/SKILL.md) | `code-tidying` | Remove comments that do not earn their keep, under a posture; audit comment residue read-only | `audit`, `report`, `safe` | `/source-control:commit`, `/review:fanout`, `/implementation:implement`, `/debugging:debug`, `/architecture:improve`, `/architecture:record-decision` |
| [`/code-tidying:tidy-diff`](../plugins/code-tidying/skills/tidy-diff/SKILL.md) | `code-tidying` | Tidy one change's own lines before its commit, scoped by a file-and-line list |  | `/source-control:commit` |
| [`/harness-ops:audit-mod-posture`](../plugins/harness-ops/skills/audit-mod-posture/SKILL.md) | `harness-ops` | Inventory installed and built-in mods with their hooks and calls, and the guard state |  | `/harness-config:audit-permission-state` |
| [`/mcp-tools:audit`](../plugins/mcp-tools/skills/audit/SKILL.md) | `mcp-tools` | Audit MCP tool definitions against design quality criteria |  |  |
| [`/mcp-tools:audit-posture`](../plugins/mcp-tools/skills/audit-posture/SKILL.md) | `mcp-tools` | Inventory configured MCP servers and flag floating versions and other supply-chain risks |  | `/harness-config:audit` |
| [`/plugin-quality:audit`](../plugins/plugin-quality/skills/audit/SKILL.md) | `plugin-quality` | Behavioral audit of a plugin component ending in a maintainer work item | `session`, `arm` | `/work-items:work` |
| [`/review:code-review`](../plugins/review/skills/code-review/SKILL.md) | `review` | Org CI code-review lane command for a GitHub pull request |  |  |
| [`/review:council`](../plugins/review/skills/council/SKILL.md) | `review` | Configurable reviewer panel chosen per change, with optional fix rounds |  | `/review:fanout`, `/verification:confirm` |
| [`/review:explain-change`](../plugins/review/skills/explain-change/SKILL.md) | `review` | Change digest for a pull request, markdown record plus an interactive view | `pr-number` | `/review:quality-gate` |
| [`/review:fanout`](../plugins/review/skills/fanout/SKILL.md) | `review` | Fan review out across every reviewer surface into one ranked report | `run-everything`, `fix` | `/review:fanout`, `/verification:confirm`, `/review:council` |
| [`/review:merge-risk`](../plugins/review/skills/merge-risk/SKILL.md) | `review` | Checked merge-risk rating of one pull request with a demote-only flag | `pr-number`, `pr-url` | `/review:explain-change` |
| [`/review:quality-gate`](../plugins/review/skills/quality-gate/SKILL.md) | `review` | Single-lens review checkpoint routed to the matching reviewer | `self`, `code`, `code-design`, `architecture`, `security`, `spec`, `close-out`, `downstream`, `pr`, `criteria`, `slice` | `/verification:confirm` |
| [`/review:security-review`](../plugins/review/skills/security-review/SKILL.md) | `review` | Org CI security-review lane command for a GitHub pull request |  |  |
| [`/skill-quality:check`](../plugins/skill-quality/skills/check/SKILL.md) | `skill-quality` | Static QA gate for skill frontmatter, caps, and evals | `check`, `validate-evals`, `listing-budget`, `measure-invocation` | `/playbooks:skill-authoring`, `/verification:confirm` |
| [`/toolchain:ratchet`](../plugins/toolchain/skills/ratchet/SKILL.md) | `toolchain` | Hold a count in CI with a checked-in ceiling a human merges |  | `/source-control:pull-request` |
| [`/user-interface:audit`](../plugins/user-interface/skills/audit/SKILL.md) | `user-interface` | Review interface code read-only by concern lane, with severity and evidence per finding | `diff`, `tree`, `launch` | `/user-interface:write-animation` |

## 11. Verify outcome

| Skill | Plugin | What it does | Actions | Next |
| --- | --- | --- | --- | --- |
| [`/performance:protect`](../plugins/performance/skills/protect/SKILL.md) | `performance` | Hold a verified counter win with a CI ceiling a human merges |  | `/toolchain:ratchet`, `/source-control:pull-request` |
| [`/performance:snapshot`](../plugins/performance/skills/snapshot/SKILL.md) | `performance` | Capture a snapshot only from a host proven measurable | `baseline`, `post` | `/implementation:implement`, `/performance:snapshot`, `/performance:climb`, `/performance:verify` |
| [`/performance:verify`](../plugins/performance/skills/verify/SKILL.md) | `performance` | Re-derive the result in fresh context and report it honestly |  | `/performance:protect`, `/source-control:pull-request`, `/performance:target`, `/debugging:debug` |
| [`/playwright:demo-video`](../plugins/playwright/skills/demo-video/SKILL.md) | `playwright` | Replay a web flow, render a produced demo video, quality-control it from frames, post it to the PR |  | `/playwright:playwright`, `/source-control:pull-request` |
| [`/toolchain:check`](../plugins/toolchain/skills/check/SKILL.md) | `toolchain` | Build, test, and lint changed files across detected ecosystems |  | `/verification:confirm`, `/testing:diagnose` |
| [`/toolchain:lint`](../plugins/toolchain/skills/lint/SKILL.md) | `toolchain` | Polyglot lint and format checks without a full build |  |  |
| [`/verification:confirm`](../plugins/verification/skills/confirm/SKILL.md) | `verification` | Prove the change achieved its intended outcome with evidence | `outcome`, `fix`, `refactor` | `/source-control:pull-request`, `/verification:measure`, `/verification:confirm`, `/app-control:map`, `/corrections:codify` |
| [`/verification:measure`](../plugins/verification/skills/measure/SKILL.md) | `verification` | Verify an improvement claim against a pre-change baseline | `performance`, `metrics` | `/verification:confirm`, `/performance:snapshot` |

## 12. Retrospective

| Skill | Plugin | What it does | Actions | Next |
| --- | --- | --- | --- | --- |
| [`/corrections:codify`](../plugins/corrections/skills/codify/SKILL.md) | `corrections` | Count a recurring mistake, pick the strongest rung and prove the check | `findings`, `reviews`, `note`, `preferences`, `group` | `/harness-config:audit-automation-gaps`, `/architecture:improve`, `/corrections:codify`, `/implementation:implement` |
| [`/session-flow:audit-friction`](../plugins/session-flow/skills/audit-friction/SKILL.md) | `session-flow` | Mine sessions for permission and autonomy friction and end in one decision brief |  | `/session-flow:audit-friction` |
| [`/session-flow:audit-sessions`](../plugins/session-flow/skills/audit-sessions/SKILL.md) | `session-flow` | Cross-session audit of transcripts with routed, never-applied findings | `sweep`, `pr`, `trends` | `/corrections:codify`, `/session-flow:audit-friction` |
| [`/session-flow:retro`](../plugins/session-flow/skills/retro/SKILL.md) | `session-flow` | Structured session retrospective with codified learnings | `session`, `quick` | `/session-flow:audit-sessions` |
| [`/session-flow:running-retro`](../plugins/session-flow/skills/running-retro/SKILL.md) | `session-flow` | In-flight retro checkpoint appended to a running ledger | `topic`, `arm` | `/session-flow:retro` |

## Ship: PR lifecycle (after stage 11)

| Skill | Plugin | What it does | Actions | Next |
| --- | --- | --- | --- | --- |
| [`/source-control:pull-request`](../plugins/source-control/skills/pull-request/SKILL.md) | `source-control` | Full PR lifecycle. Prep, create, monitor CI, address reviews, merge | `prep`, `create`, `ready`, `monitor`, `comments`, `ci`, `merge`, `reassess`, `evidence`, `status`, `full` | `/session-flow:retro`, `/implementation:implement`, `/explainer-video:produce` |

## Anytime / cross-cutting

| Skill | Plugin | What it does | Actions | Next |
| --- | --- | --- | --- | --- |
| [`/adhd:clarify`](../plugins/adhd/skills/clarify/SKILL.md) | `adhd` | Reshape a dense, decision-heavy message into clear one-decision-at-a-time chunks, losing nothing |  |  |
| [`/adhd:shape`](../plugins/adhd/skills/shape/SKILL.md) | `adhd` | Set a standing action-first output posture. Lead with the next action, cut preamble |  |  |
| [`/ai-slop:audit`](../plugins/ai-slop/skills/audit/SKILL.md) | `ai-slop` | Detect and remove AI-writing tells from markdown, commit messages, PR bodies and interface copy | `audit`, `fix` |  |
| [`/architecture:principles`](../plugins/architecture/skills/principles/SKILL.md) | `architecture` | Define the module-design terms architecture findings use |  | `/architecture:improve` |
| [`/architecture:record-decision`](../plugins/architecture/skills/record-decision/SKILL.md) | `architecture` | Record an architecture decision in the repository's existing ADR convention |  | `/planning:plan` |
| [`/attribution:audit`](../plugins/attribution/skills/audit/SKILL.md) | `attribution` | Find prose copied from external sources and convert it into pointers | `audit`, `fix`, `sweep` |  |
| [`/code-metrics:audit`](../plugins/code-metrics/skills/audit/SKILL.md) | `code-metrics` | Lines, complexity and typed-code numbers beside cited references, no verdict | `size`, `complexity`, `type-debt` | `/verification:measure`, `/code-metrics:audit-coverage`, `/code-metrics:principles` |
| [`/code-metrics:audit-coverage`](../plugins/code-metrics/skills/audit-coverage/SKILL.md) | `code-metrics` | Coverage and CRAP read from build artifacts, no verdict |  | `/verification:measure`, `/mutation-testing:audit`, `/code-metrics:principles` |
| [`/code-metrics:audit-duplication`](../plugins/code-metrics/skills/audit-duplication/SKILL.md) | `code-metrics` | Clone groups minus the replication the repo declares, no verdict |  | `/verification:measure`, `/code-metrics:principles` |
| [`/code-metrics:audit-suppressions`](../plugins/code-metrics/skills/audit-suppressions/SKILL.md) | `code-metrics` | Suppressions with their rule ids and reasons, no verdict |  | `/toolchain:ratchet`, `/review:fanout`, `/code-metrics:principles` |
| [`/code-metrics:principles`](../plugins/code-metrics/skills/principles/SKILL.md) | `code-metrics` | What each code measure can and cannot tell you |  | `/code-metrics:audit`, `/code-metrics:setup` |
| [`/code-tidying:audit-dead-code`](../plugins/code-tidying/skills/audit-dead-code/SKILL.md) | `code-tidying` | Whole-repo dead-code hunt across four labeled lanes with adjudicated candidates |  | `/code-tidying:tidy` |
| [`/code-tidying:tidy`](../plugins/code-tidying/skills/tidy/SKILL.md) | `code-tidying` | Proactively hunt one lane for safe structural tidyings and ship a structure-only PR | `dry-run`, `self-update`, `help` | `/source-control:babysit-prs` |
| [`/codebase-health:audit`](../plugins/codebase-health/skills/audit/SKILL.md) | `codebase-health` | Audit for drift between docs, config, code, and architecture via verified findings |  | `/implementation:implement`, `/verification:confirm` |
| [`/computer-use:diagnose`](../plugins/computer-use/skills/diagnose/SKILL.md) | `computer-use` | Resolve computer-use capture, input, and screenshot symptoms to a cause | `screenshots`, `failures`, `quirks` |  |
| [`/context-budget:audit`](../plugins/context-budget/skills/audit/SKILL.md) | `context-budget` | Measure the startup context payload per item and ledger every lever's real delta | `fix` |  |
| [`/coupling:reduce`](../plugins/coupling/skills/reduce/SKILL.md) | `coupling` | Scan for change-transmitting coupling, apply safe reductions in a budgeted batch, route the rest | `dry-run`, `change`, `status`, `help` | `/verification:confirm` |
| [`/developer-experience:audit-tools`](../plugins/developer-experience/skills/audit-tools/SKILL.md) | `developer-experience` | Inventory a repository's developer tooling and report findings, read-only by default |  | `/developer-experience:build-cli`, `/overengineering:justify` |
| [`/discipline:be-ambitious`](../plugins/discipline/skills/be-ambitious/SKILL.md) | `discipline` | Raise a request before work and wait, or deepen finished work and redo it with an outside check |  | `/planning:interview` |
| [`/discipline:do-your-research`](../plugins/discipline/skills/do-your-research/SKILL.md) | `discipline` | Re-anchor research discipline, then audit and correct the current work | `tiered`, `full` | `/discovery:research` |
| [`/discipline:follow-our-standards`](../plugins/discipline/skills/follow-our-standards/SKILL.md) | `discipline` | Re-anchor to org engineering standards and audit the work in flight |  |  |
| [`/discipline:hold-my-hand`](../plugins/discipline/skills/hold-my-hand/SKILL.md) | `discipline` | Standing posture. Phase the work, present one phase at a time, wait for the advancing reply |  |  |
| [`/discipline:mind-your-maxims`](../plugins/discipline/skills/mind-your-maxims/SKILL.md) | `discipline` | Re-anchor cooperative communication and audit recent responses for clarity |  |  |
| [`/discipline:pick-for-the-problem`](../plugins/discipline/skills/pick-for-the-problem/SKILL.md) | `discipline` | Re-derive a tool or approach choice from the problem, not habit |  |  |
| [`/discipline:point-dont-copy`](../plugins/discipline/skills/point-dont-copy/SKILL.md) | `discipline` | Audit for copied content and correct by pointing at the living source |  |  |
| [`/discipline:reason-dont-recite`](../plugins/discipline/skills/reason-dont-recite/SKILL.md) | `discipline` | Challenge decisions coasting on precedent, re-derive from first principles |  |  |
| [`/discipline:recheck-against-upstream`](../plugins/discipline/skills/recheck-against-upstream/SKILL.md) | `discipline` | Audit the surface in flight against current official upstream docs |  |  |
| [`/discipline:reuse-or-replace`](../plugins/discipline/skills/reuse-or-replace/SKILL.md) | `discipline` | Reuse the established way or openly replace it, never a silent second way |  |  |
| [`/discipline:script-the-deterministic-work`](../plugins/discipline/skills/script-the-deterministic-work/SKILL.md) | `discipline` | Script counting, diffing, and transforms instead of eyeballing them |  | `/implementation:implement`, `/harness-config:audit-automation-gaps` |
| [`/discipline:scrutinize-dont-coast`](../plugins/discipline/skills/scrutinize-dont-coast/SKILL.md) | `discipline` | Re-examine your own recent output through a fresh-context pass |  |  |
| [`/discipline:sweep-all`](../plugins/discipline/skills/sweep-all/SKILL.md) | `discipline` | Batch every discipline corrector into one audited re-anchor pass |  |  |
| [`/discipline:tighten-your-output`](../plugins/discipline/skills/tighten-your-output/SKILL.md) | `discipline` | Tighten prose and code. Fewer words, no semantic loss |  |  |
| [`/discipline:use-your-skills`](../plugins/discipline/skills/use-your-skills/SKILL.md) | `discipline` | Map the task to available skills and invoke them instead of reinventing |  |  |
| [`/discipline:wait-what`](../plugins/discipline/skills/wait-what/SKILL.md) | `discipline` | Re-pitch the message that did not land. Missing context added, plain register, project vocabulary |  |  |
| [`/disk-hygiene:audit`](../plugins/disk-hygiene/skills/audit/SKILL.md) | `disk-hygiene` | Scan a directory tree for stale leftovers and report the evidence, read-only |  | `/disk-hygiene:clean` |
| [`/disk-hygiene:clean`](../plugins/disk-hygiene/skills/clean/SKILL.md) | `disk-hygiene` | Audit a directory tree for stale leftovers and remove validated paths |  |  |
| [`/docs-hygiene:audit-derivability`](../plugins/docs-hygiene/skills/audit-derivability/SKILL.md) | `docs-hygiene` | Judge whether a doc earns its existence or should become a pointer | `target`, `audit`, `sweep` |  |
| [`/docs-hygiene:audit-encapsulation`](../plugins/docs-hygiene/skills/audit-encapsulation/SKILL.md) | `docs-hygiene` | Find external citations reaching into a skill's private surfaces | `detect`, `sweep`, `file-issues` |  |
| [`/docs-hygiene:audit-noise`](../plugins/docs-hygiene/skills/audit-noise/SKILL.md) | `docs-hygiene` | Classify markdown for citations, ghost refs, meta-commentary, plan/conversational/tracker residue |  | `/review:fanout`, `/docs-hygiene:audit-derivability`, `/docs-hygiene:compress` |
| [`/docs-hygiene:audit-progressive-disclosure`](../plugins/docs-hygiene/skills/audit-progressive-disclosure/SKILL.md) | `docs-hygiene` | Grade instruction files for split opportunities and hub/spoke disclosure defects |  | `/docs-hygiene:write-for-agents`, `/docs-hygiene:compress`, `/docs-hygiene:rename-references` |
| [`/docs-hygiene:compress`](../plugins/docs-hygiene/skills/compress/SKILL.md) | `docs-hygiene` | Tighten markdown by dropping flavor while preserving every directive | `audit`, `compare`, `target` |  |
| [`/docs-hygiene:extract-ssot`](../plugins/docs-hygiene/skills/extract-ssot/SKILL.md) | `docs-hygiene` | Deduplicate repeated prose into one named source of truth | `identify`, `verify`, `plan`, `execute`, `batch`, `unwind` |  |
| [`/docs-hygiene:rename-references`](../plugins/docs-hygiene/skills/rename-references/SKILL.md) | `docs-hygiene` | Sweep stale references after renames, including forms grep misses | `audit`, `preview`, `blocklist` | `/docs-naming:audit-file-names` |
| [`/docs-hygiene:write-for-agents`](../plugins/docs-hygiene/skills/write-for-agents/SKILL.md) | `docs-hygiene` | Authoring-time doctrine for agent-consumed markdown |  |  |
| [`/docs-hygiene:write-for-humans`](../plugins/docs-hygiene/skills/write-for-humans/SKILL.md) | `docs-hygiene` | Authoring-time doctrine for human-read documentation |  |  |
| [`/docs-naming:audit-file-names`](../plugins/docs-naming/skills/audit-file-names/SKILL.md) | `docs-naming` | Inventory a doc tree's file names and plan the renames with their references |  | `/docs-naming:realign-file-names` |
| [`/docs-naming:realign-file-names`](../plugins/docs-naming/skills/realign-file-names/SKILL.md) | `docs-naming` | Apply a file-name rename plan, one acceptance per file |  |  |
| [`/education:explain`](../plugins/education/skills/explain/SKILL.md) | `education` | Explain any concept or the last response in genuinely plain words |  | `/education:teach`, `/education:illustrate` |
| [`/education:illustrate`](../plugins/education/skills/illustrate/SKILL.md) | `education` | Visual explainer for a concept or codebase topic, record plus interactive page |  | `/education:teach`, `/education:quiz-me` |
| [`/education:quiz-me`](../plugins/education/skills/quiz-me/SKILL.md) | `education` | Generate a post-change report with a quiz verifying you absorbed the work |  |  |
| [`/education:teach`](../plugins/education/skills/teach/SKILL.md) | `education` | Multi-session learning coach for general topics or repo-grounded concepts | `topic`, `codebase`, `mission`, `glossary`, `resources`, `explain`, `primer`, `exercise`, `assess`, `resume`, `status` |  |
| [`/fleet:reach`](../plugins/fleet/skills/reach/SKILL.md) | `fleet` | Reach another fleet lane (WSL or Windows, here or remote) to run, prompt, query or message |  |  |
| [`/github:advise`](../plugins/github/skills/advise/SKILL.md) | `github` | Design and set up GitHub settings and admin areas grounded in live gh state |  |  |
| [`/github:audit`](../plugins/github/skills/audit/SKILL.md) | `github` | Read-only audit of GitHub org and repo settings, drift, and cost signals |  |  |
| [`/harness-config:audit`](../plugins/harness-config/skills/audit/SKILL.md) | `harness-config` | Audit settings, hooks, permissions, and MCP config for drift against current official docs |  | `/harness-config:audit-permission-grants`, `/harness-config:audit-automation-gaps`, `/harness-config:audit-pass` |
| [`/harness-config:audit-automation-gaps`](../plugins/harness-config/skills/audit-automation-gaps/SKILL.md) | `harness-config` | Audit the repo's automation landscape for hook, MCP, skill, and subagent gaps worth adding |  | `/planning:plan`, `/work-items:decompose`, `/overengineering:audit`, `/work-items:track` |
| [`/harness-config:audit-instructions`](../plugins/harness-config/skills/audit-instructions/SKILL.md) | `harness-config` | Find instructions current models no longer need across CLAUDE.md, AGENTS.md, rules, and skill bodies |  | `/harness-config:unhobble`, `/harness-memory:audit`, `/instruction-placement:migrate`, `/harness-config:audit-prompting-postures` |
| [`/harness-config:audit-pass`](../plugins/harness-config/skills/audit-pass/SKILL.md) | `harness-config` | Run one coordinated, resumable audit pass over a repo with a single human gate |  |  |
| [`/harness-config:audit-permission-grants`](../plugins/harness-config/skills/audit-permission-grants/SKILL.md) | `harness-config` | Audit permission grants for portability and auto-mode durability | `frontmatter`, `settings`, `plugins`, `all` | `/harness-config:audit-permission-state`, `/harness-config:audit` |
| [`/harness-config:audit-permission-state`](../plugins/harness-config/skills/audit-permission-state/SKILL.md) | `harness-config` | Report the permission rules actually in effect and what auto mode drops |  |  |
| [`/harness-config:audit-prompting-postures`](../plugins/harness-config/skills/audit-prompting-postures/SKILL.md) | `harness-config` | Find posture guidance the prompting guide says a component needs but does not carry | `skills`, `agents`, `hooks`, `output-styles`, `claude-md`, `rules`, `all` |  |
| [`/harness-config:draft-auto-mode-rules`](../plugins/harness-config/skills/draft-auto-mode-rules/SKILL.md) | `harness-config` | Interview and draft a paste-ready autoMode block, never writing settings | `environment`, `allow` |  |
| [`/harness-config:unhobble`](../plugins/harness-config/skills/unhobble/SKILL.md) | `harness-config` | Strip instructions to a bare baseline, log real stumbles, re-add only what evidence earns | `snapshot`, `bare`, `observe`, `readd`, `watch`, `status`, `decide` |  |
| [`/harness-memory:audit`](../plugins/harness-memory/skills/audit/SKILL.md) | `harness-memory` | Audit CLAUDE.md, a root AGENTS.md, rules, and auto-memory against the official-docs checklist | `audit`, `fix`, `update`, `report` |  |
| [`/harness-memory:stateless`](../plugins/harness-memory/skills/stateless/SKILL.md) | `harness-memory` | Inspect, disable, or purge Claude Code's per-repo auto memory | `status`, `disable`, `purge` |  |
| [`/harness-ops:audit-plugin-landscape`](../plugins/harness-ops/skills/audit-plugin-landscape/SKILL.md) | `harness-ops` | Report plugin and marketplace staleness, overlaps and alternatives; recommend only |  |  |
| [`/harness-ops:behavior-probes`](../plugins/harness-ops/skills/behavior-probes/SKILL.md) | `harness-ops` | Run data-driven live probes of Claude Code permission and platform behavior and record the outcomes | `validate`, `dry-run`, `live`, `recheck` | `/harness-ops:changelog` |
| [`/harness-ops:changelog`](../plugins/harness-ops/skills/changelog/SKILL.md) | `harness-ops` | Ingest a Claude Code release changelog and integrate its changes into the repo | `fetch`, `diff`, `status`, `apply` | `/harness-ops:audit-native-overlap`, `/work-items:triage`, `/harness-ops:inventory`, `/harness-ops:behavior-probes` |
| [`/harness-ops:known-issues`](../plugins/harness-ops/skills/known-issues/SKILL.md) | `harness-ops` | Look up and track known Claude product issues, health, and workarounds | `status`, `search`, `check-all`, `scan`, `list`, `quality`, `create` |  |
| [`/improvement:find`](../plugins/improvement/skills/find/SKILL.md) | `improvement` | Rank evidence-cited improvement candidates across dimensions; execution goes to the pipeline |  | `/improvement:improve`, `/planning:interview` |
| [`/improvement:improve`](../plugins/improvement/skills/improve/SKILL.md) | `improvement` | Find one gap in a target against a stated standard and ship the fix as one PR |  | `/source-control:pull-request`, `/planning:plan` |
| [`/instruction-placement:audit`](../plugins/instruction-placement/skills/audit/SKILL.md) | `instruction-placement` | Find instruction content on the wrong surface and propose validated destinations | `core`, `expanded` | `/instruction-placement:realign`, `/instruction-placement:migrate` |
| [`/instruction-placement:check`](../plugins/instruction-placement/skills/check/SKILL.md) | `instruction-placement` | Gate that every path-scoped rule glob resolves and the rules index is current |  | `/instruction-placement:realign` |
| [`/instruction-placement:delta`](../plugins/instruction-placement/skills/delta/SKILL.md) | `instruction-placement` | Report only what moved since the last placement audit |  | `/instruction-placement:realign` |
| [`/multi-agent:audit-defaults`](../plugins/multi-agent/skills/audit-defaults/SKILL.md) | `multi-agent` | Recheck the routing defaults against their upstream sources | `fanout`, `repo` | `/multi-agent:route` |
| [`/overengineering:audit`](../plugins/overengineering/skills/audit/SKILL.md) | `overengineering` | Audit the enforcement surface for mechanisms no longer earning their carry cost |  | `/overengineering:realign` |
| [`/overengineering:delta`](../plugins/overengineering/skills/delta/SKILL.md) | `overengineering` | Re-run the enforcement-surface audit and report only what moved since the last run |  | `/overengineering:realign` |
| [`/overengineering:justify`](../plugins/overengineering/skills/justify/SKILL.md) | `overengineering` | Make one artifact, or one proposal before it is built, justify its existence on evidence | `path`, `proposal` | `/overengineering:realign`, `/planning:plan` |
| [`/playbooks:boris`](../plugins/playbooks/skills/boris/SKILL.md) | `playbooks` | Boris Cherny's Claude Code workflow tips across 131 sections (130 upstream, L1 local) |  |  |
| [`/playbooks:fable-5`](../plugins/playbooks/skills/fable-5/SKILL.md) | `playbooks` | Fable 5.2's operating doctrine loaded as standing session instructions | `full` |  |
| [`/playbooks:repo-sweep`](../plugins/playbooks/skills/repo-sweep/SKILL.md) | `playbooks` | Run the hygiene skill catalog through one repo, one PR, one commit per step | `plan`, `next`, `review` | `/source-control:pull-request` |
| [`/playbooks:skill-authoring`](../plugins/playbooks/skills/skill-authoring/SKILL.md) | `playbooks` | Anthropic's internal skill-authoring playbook and patterns |  | `/skill-quality:check` |
| [`/playgrounds:use`](../plugins/playgrounds/skills/use/SKILL.md) | `playgrounds` | Route playground requests to the first-party plugin, or install it, with recipes and guidance |  |  |
| [`/repo-hygiene:clean`](../plugins/repo-hygiene/skills/clean/SKILL.md) | `repo-hygiene` | Clean caches, build artifacts, stale branches, and stashes per repo | `scan`, `caches`, `build`, `git`, `stash`, `tree`, `all`, `aliases` | `/source-control:worktree`, `/repo-fleet-hygiene:audit`, `/disk-hygiene:clean` |
| [`/session-flow:recommend-skills`](../plugins/session-flow/skills/recommend-skills/SKILL.md) | `session-flow` | Lay out the skills that fit this moment as a ranked, nothing-hidden menu | `topic-slug`, `question` | `/session-flow:workflow` |
| [`/session-flow:workflow`](../plugins/session-flow/skills/workflow/SKILL.md) | `session-flow` | Navigate the staged dev workflow and suggest the next stage | `steps`, `pre-pr`, `wrap-up`, `philosophy`, `spec-first`, `continue` |  |
| [`/user-experience:evaluate`](../plugins/user-experience/skills/evaluate/SKILL.md) | `user-experience` | Plan and run UX evaluations, fair-choice checks and measure selection, evidence-labeled |  |  |
| [`/user-experience:plan-user-research`](../plugins/user-experience/skills/plan-user-research/SKILL.md) | `user-experience` | Plan user research and write its instruments, evidence-labeled |  | `/user-experience:synthesize` |
| [`/user-experience:shape`](../plugins/user-experience/skills/shape/SKILL.md) | `user-experience` | Detect the app's stage and the project's own evidence, then chain the UX jobs in order |  | `/user-interface:design`, `/user-experience:setup` |
| [`/user-experience:synthesize`](../plugins/user-experience/skills/synthesize/SKILL.md) | `user-experience` | Synthesize research data into labeled themes, insights, needs, personas or jobs |  | `/user-experience:structure` |
| [`/user-interface:glossary`](../plugins/user-interface/skills/glossary/SKILL.md) | `user-interface` | Name the design or front-end term for a described effect, detail or behavior |  | `/user-interface:write-animation`, `/user-interface:write-css` |
| [`/visualization:present`](../plugins/visualization/skills/present/SKILL.md) | `visualization` | Slide deck through the claude.ai Slides Artifact type, outline markdown as the record |  | `/visualization:visualize` |
| [`/visualization:visualize`](../plugins/visualization/skills/visualize/SKILL.md) | `visualization` | Pick the best visual form for what is in the conversation and render it |  | `/visualization:present` |
| [`/wizard:generate`](../plugins/wizard/skills/generate/SKILL.md) | `wizard` | Author a hardened interactive bash wizard for human-only setup, credential, and cutover steps |  | `/wizard:unattended` |
| [`/wizard:unattended`](../plugins/wizard/skills/unattended/SKILL.md) | `wizard` | Author an unattended script a human launches once for a privilege or policy boundary |  | `/wizard:generate` |
| [`/work-items:measure-delivery`](../plugins/work-items/skills/measure-delivery/SKILL.md) | `work-items` | Report the five DORA delivery metrics as a team trend from default-branch history |  | `/work-items:track` |
| [`/work-items:scan-todos`](../plugins/work-items/skills/scan-todos/SKILL.md) | `work-items` | Sweep source comments for TODO and FIXME markers, resolve or file each |  | `/work-items:triage` |
| [`/work-items:ship`](../plugins/work-items/skills/ship/SKILL.md) | `work-items` | Route and run a spec container's macro journey. Status, execution shape, next step | `status`, `run` | `/work-items:work`, `/work-items:ship` |
| [`/work-items:track`](../plugins/work-items/skills/track/SKILL.md) | `work-items` | Backlog CRUD through the bound tracker. Add, list, close, stats | `stats`, `list`, `add`, `start`, `done`, `due`, `recheck`, `search`, `audit`, `publish-plan`, `link`, `view`, `edit`, `changes` | `/work-items:work`, `/work-items:triage` |
| [`/work-items:triage`](../plugins/work-items/skills/triage/SKILL.md) | `work-items` | Evaluate raw intake through the verified-to-eligible state machine |  | `/work-items:work`, `/planning:interview`, `/debugging:debug`, `/work-items:decompose` |
| [`/work-items:work`](../plugins/work-items/skills/work/SKILL.md) | `work-items` | Auto-select one work item and execute it end-to-end |  | `/source-control:babysit-prs`, `/work-items:work` |
| [`/writing:be-concise`](../plugins/writing/skills/be-concise/SKILL.md) | `writing` | Reshape prose for a scanning reader. Bottom line first, about half the words |  |  |

## Session lifecycle

| Skill | Plugin | What it does | Actions | Next |
| --- | --- | --- | --- | --- |
| [`/multi-agent:assess`](../plugins/multi-agent/skills/assess/SKILL.md) | `multi-agent` | Decide workflow, subagents or one context for a task |  | `/multi-agent:route`, `/session-flow:orchestrate` |
| [`/multi-agent:route`](../plugins/multi-agent/skills/route/SKILL.md) | `multi-agent` | Resolve model and effort per agent role for a multi-agent run | `all` | `/multi-agent:audit-defaults` |
| [`/session-flow:clean-stop`](../plugins/session-flow/skills/clean-stop/SKILL.md) | `session-flow` | Make everything durable before the machine goes away |  |  |
| [`/session-flow:continue-in-background`](../plugins/session-flow/skills/continue-in-background/SKILL.md) | `session-flow` | Delegate the task to a fresh background agent now |  |  |
| [`/session-flow:find-handoff`](../plugins/session-flow/skills/find-handoff/SKILL.md) | `session-flow` | Recover a lost handoff or resume prompt after /clear |  |  |
| [`/session-flow:handoff`](../plugins/session-flow/skills/handoff/SKILL.md) | `session-flow` | Write a mid-session save-point for clear-and-resume | `file`, `prompt` | `/session-flow:find-handoff`, `/session-flow:reanchor` |
| [`/session-flow:keep-going`](../plugins/session-flow/skills/keep-going/SKILL.md) | `session-flow` | Recover after an interruption and continue where work stood |  | `/session-flow:workflow` |
| [`/session-flow:orchestrate`](../plugins/session-flow/skills/orchestrate/SKILL.md) | `session-flow` | Arm the session with proactive-orchestration imperatives | `handoff`, `worker`, `coordinator` | `/planning:draft-goal-condition` |
| [`/session-flow:orient`](../plugins/session-flow/skills/orient/SKILL.md) | `session-flow` | Read-only situation report from durable and off-thread state | `catch-up`, `zoom-out` |  |
| [`/session-flow:reanchor`](../plugins/session-flow/skills/reanchor/SKILL.md) | `session-flow` | Verify working assumptions are still true before building on them |  |  |
| [`/session-flow:recall`](../plugins/session-flow/skills/recall/SKILL.md) | `session-flow` | Topic history from past transcripts, reverts, closed PRs and tracker items |  | `/session-flow:orient` |
| [`/session-flow:reconcile`](../plugins/session-flow/skills/reconcile/SKILL.md) | `session-flow` | Retire finished off-thread work and square the task ledger |  |  |
| [`/session-flow:tidy-work`](../plugins/session-flow/skills/tidy-work/SKILL.md) | `session-flow` | Report, normalize, and clean stale .work memory items | `report`, `normalize`, `clean` | `/session-flow:clean-stop` |
| [`/source-control:worktree`](../plugins/source-control/skills/worktree/SKILL.md) | `source-control` | Create, inspect, and clean git worktrees for parallel sessions | `create`, `status`, `cleanup`, `audit` |  |

## Operator cadence

| Skill | Plugin | Cadence | What it does | Actions | Next |
| --- | --- | --- | --- | --- | --- |
| [`/bugs:scan`](../plugins/bugs/skills/scan/SKILL.md) | `bugs` | daily | Proactively hunt resting code for unobserved bugs, verify adversarially, report read-only |  | `/implementation:implement`, `/work-items:track`, `/review:security-review`, `/debugging:debug` |
| [`/harness-ops:audit-install-state`](../plugins/harness-ops/skills/audit-install-state/SKILL.md) | `harness-ops` | weekly | Audit a Claude Code install directory. What is there, what the product manages, what is stale |  | `/disk-hygiene:clean` |
| [`/harness-ops:audit-native-overlap`](../plugins/harness-ops/skills/audit-native-overlap/SKILL.md) | `harness-ops` | weekly | Map native Claude Code surfaces against this repo's components and record owner-directed verdicts | `report`, `apply`, `dismiss` |  |
| [`/harness-ops:audit-performance`](../plugins/harness-ops/skills/audit-performance/SKILL.md) | `harness-ops` | continuous | Capture slowness evidence while slow. Version, sweep health, tree walk, sessions, fleet, fan-out |  |  |
| [`/harness-ops:audit-skill-visibility`](../plugins/harness-ops/skills/audit-skill-visibility/SKILL.md) | `harness-ops` | weekly | Which skills the model can actually see, which are starved, and which are unobservable |  |  |
| [`/harness-ops:inventory`](../plugins/harness-ops/skills/inventory/SKILL.md) | `harness-ops` | weekly | Enumerate every command, skill, agent, and plugin component this machine can invoke |  | `/harness-ops:audit-native-overlap` |
| [`/harness-ops:lanes`](../plugins/harness-ops/skills/lanes/SKILL.md) | `harness-ops` | daily | Start, restart, stop, and check loop lanes as named background sessions | `start`, `restart`, `status`, `stop`, `run-once`, `print-schedule`, `consume-restarts` |  |
| [`/harness-ops:machine-profile`](../plugins/harness-ops/skills/machine-profile/SKILL.md) | `harness-ops` | weekly | Discover, store and diff machine facts and per-tree identity domains. Read-only by default. | `profile`, `diff`, `explain`, `apply` | `/harness-ops:prerequisites`, `/harness-ops:plugins-audit` |
| [`/harness-ops:observability`](../plugins/harness-ops/skills/observability/SKILL.md) | `harness-ops` | weekly | Report on locally captured telemetry. Token burn, cost, hook latency, per-session activity | `week`, `session`, `day`, `month`, `all`, `clean`, `latency`, `compare`, `items`, `hooks` |  |
| [`/harness-ops:plugins`](../plugins/harness-ops/skills/plugins/SKILL.md) | `harness-ops` | weekly | Bring the machine's plugin fleet current. Refresh, update, install per policy | `sync`, `converge` | `/harness-ops:prerequisites` |
| [`/harness-ops:plugins-audit`](../plugins/harness-ops/skills/plugins-audit/SKILL.md) | `harness-ops` | weekly | Predict what plugin sync would change, read-only | `all` | `/harness-ops:plugins` |
| [`/harness-ops:prerequisites`](../plugins/harness-ops/skills/prerequisites/SKILL.md) | `harness-ops` | weekly | Report external tools the enabled fleet declares missing. Never installs. |  | `/harness-ops:machine-profile`, `/harness-ops:plugins-audit` |
| [`/repo-fleet-hygiene:apply`](../plugins/repo-fleet-hygiene/skills/apply/SKILL.md) | `repo-fleet-hygiene` | weekly | Execute a fleet action plan behind one confirmation gate |  |  |
| [`/repo-fleet-hygiene:audit`](../plugins/repo-fleet-hygiene/skills/audit/SKILL.md) | `repo-fleet-hygiene` | weekly | Discover a repository fleet and coordinate read-only evidence handoffs |  |  |
| [`/repo-fleet-hygiene:sync`](../plugins/repo-fleet-hygiene/skills/sync/SKILL.md) | `repo-fleet-hygiene` | weekly | Fast-forward canonical checkouts to the remote default branch |  | `/repo-fleet-hygiene:audit` |
| [`/source-control:babysit-loop`](../plugins/source-control/skills/babysit-loop/SKILL.md) | `source-control` | continuous | Run one repo's PR queue as a standing merge lane |  | `/work-items:attend-queue` |
| [`/source-control:babysit-prs`](../plugins/source-control/skills/babysit-prs/SKILL.md) | `source-control` | continuous | Tiered fleet pass advancing your open PRs | `worker`, `autopilot`, `help` |  |
| [`/work-items:attend-queue`](../plugins/work-items/skills/attend-queue/SKILL.md) | `work-items` | daily | Drive escalations to resolution; list held PRs and post-merge failures; hand intake to triage |  | `/work-items:work-loop` |
| [`/work-items:morning-brief`](../plugins/work-items/skills/morning-brief/SKILL.md) | `work-items` | daily | Print the operator's read-only morning view. Queues, merge-ready PRs, parked decisions |  |  |
| [`/work-items:work-loop`](../plugins/work-items/skills/work-loop/SKILL.md) | `work-items` | continuous | Drain the backlog as a self-paced autonomous loop |  | `/work-items:attend-queue` |

<!-- END GENERATED: cheatsheet -->
