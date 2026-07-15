# Skill-eval coverage — warrant snapshot

Point-in-time record of which shipped skills carry model-graded evals, which *warrant* them and are
owed backfill, and which are explicit **skips**. This is an **audit snapshot**, not durable policy —
the warrant rule and the consumer-verify recipe are policy and live in the
[migration playbook](MIGRATION-PLAYBOOK.md) ("Evals — warrant policy and consumer-verify recipe").
This table records where each plugin stood on the stamp date and which backfill issue owns each gap.
Empirical claims decay: a row is only true as of the stamp below.

> **Reconciliation — 2026-07-15 (taxonomy reorg).** The plugin-taxonomy reorg renamed, split, and
> merged plugins (43 → 45), so this document carries two layers, kept apart by a single temporal line:
>
> - **Current-state layer — re-scanned 2026-07-15, authoritative.** The *Current coverage* section
>   below, plus the *Deferred* and *Skip* classifications, were re-derived from a fresh glob of
>   `plugins/*/skills/*/evals/evals.json` across the live 45-plugin tree and use post-reorg names.
> - **Program-record layer — frozen at 2026-07-12.** The *Backfill program* batch table and the
>   *Future coverage* section are the dated record of the `melodic-software/medley` wave-2 backfill
>   program. They keep the pre-reorg plugin/skill identities the medley issues were filed against and
>   are **not** name-swept — the renames map in `.claude-plugin/marketplace.json` and the split
>   changelogs (`implementation` 0.6.0, `work-items` 0.7.0, `claude-config` 0.5.0) are the
>   authoritative old→new mapping.
>
> Only eval *presence* was re-verified this session; no skill's warrant classification was re-graded.

Stamped 2026-07-12, built from the per-skill eval presence read that session against the 42 plugins
then in `.claude-plugin/marketplace.json` and the class column of
[`extensibility-contract-grading.md`](extensibility-contract-grading.md) (retrofit-audit
`melodic-software/medley#1388`, which graded 41 — the `miro` MCP-server plugin landed after that audit
and is classified below). Presence was read per-skill from each `plugins/<p>/skills/<s>/evals/evals.json`;
because sibling workers backfill concurrently, that read is accurate only at its instant — the batch
table's Status column carries the reconciliation and the live tree is the source of truth.
Emitter: evals-backfill `melodic-software/medley#1396`.

## Current coverage (re-scanned 2026-07-15)

Fresh glob across the live 45-plugin tree: **92 of 102 skills carry `evals/evals.json`.** The wave-2
backfill program (batch table below) has essentially landed — every skill listed in those batches now
ships an eval. The 10 remaining uncovered skills fall into three buckets:

- **Genuine gaps — warranted, unowned (2).** `context7/setup` and `planning/wayfind` (a skill that
  postdates the wave-2 batches). Neither is owned by a listed batch (#1447 covered planning's seven
  behavior skills, not `wayfind`; the setup self-scan #1462 did not list `context7`). Identified here;
  **no backfill issue has been filed** — filing lands in `melodic-software/medley`, out of scope for
  this repo.
- **Deferred (6).** `knowledge` (`book-distill`, `setup` — `youtube` and `course-digest` now ship
  evals) and `songwriting` (`daily-practice`, `meter-prosody`, `setup`, `suno` — the other six skills
  now ship evals). Both plugins are under open move-out gates; see *Deferred* below.
- **Skip — pure-reference (2).** `tdd/principles` and `playbooks/fable-5`; see *Skip* below.

## Warrant rule (summary)

Full rule + rationale: playbook "Evals — warrant policy and consumer-verify recipe". In brief a skill
**warrants** evals when it carries a judgment-bearing behavioral contract — triggering, routing,
refusal, or output shape that could silently regress. A skill is an explicit **skip** when it is
pure-reference (answers from a corpus, no decision contract) or a **hook** (deterministic, guarded by
`.test.sh`, no model-invoked skill). Gray-zone skills are marked **author-confirm**: the backfill
session re-checks the warrant against the live `SKILL.md` and records a skip verdict if it dissolves.

## Backfill program — 2026-07-12 record (frozen)

Frozen at the 2026-07-12 stamp with the pre-reorg identities each medley issue was filed against.
**Per the 2026-07-15 live scan every skill listed below is now covered**; the table is retained as the
dated program record, not a live to-do list.

One issue per batch, each sized to one agent-session, sub-issue-linked under wave-2 map
`melodic-software/medley#1369`, `agent-ready`. Each batch issue carries the authoring recipe, the
schema path, and the per-skill warrant re-check instruction. The **Status** column is the
reconciliation as it stood at the 2026-07-12 stamp — `DONE` = all listed skills covered by concurrent
sibling backfill; `PARTIAL` = some remained; `OPEN` = none covered yet.

| Batch issue | Skills | Status (at stamp) |
|---|---|---|
| `melodic-software/medley#1447` | planning: architect, brainstorm, design, design-handoff, devils-advocate, interview, prd (7) | **DONE** — all 7 backfilled concurrently |
| `melodic-software/medley#1448` | discovery: explore, explore-deep, research, research-deep, setup; claude-config-audit: memory-health (6) | **PARTIAL** — only `discovery/setup` remains; the other 5 backfilled concurrently |
| `melodic-software/medley#1449` | implementation: implement, implement-dispatch, build, lint, setup (5) | **OPEN** — #1420 (ecosystem-commands + setup) CLOSED → stable; build/lint/setup author-confirm |
| `melodic-software/medley#1450` | docs-hygiene: compress, declutter, encapsulation-audit, extract-ssot, rename-references (5) | **OPEN** |
| `melodic-software/medley#1451` | session-flow: handoff, orchestration-brief, retro, workflow; source-control: commit, pull-request, worktree (7) | **OPEN** |
| `melodic-software/medley#1452` | claude-ops: claude-code-changelog, claude-observability, claude-troubleshooting; prototype: logic, ui (5) | **DONE** — all 5 backfilled concurrently |
| `melodic-software/medley#1453` | context7, firecrawl, playwright, diagnose, teach, kindle-dedrm (6) | **DONE** — all 6 backfilled concurrently |
| `melodic-software/medley#1454` | event-storming: methodology, simulation; machine-health: machine-health, setup; skill-quality: skill-quality, setup (6) | **OPEN** — author vs current shipped behavior; owning retrofits update their eval on behavior change (simulation #1405, machine-health #1419, skill-quality #1418) |
| `melodic-software/medley#1455` | review-toolkit: quality-gate, code-review-fanout (2) | **OPEN** — #1421 CLOSED → stable; the six reviewer agents are not skills and carry no `evals/` slot |
| `melodic-software/medley#1458` | boris, thariq-skills (2) | **DONE** — both backfilled concurrently; reclassified from pure-reference for their `update`/`update --apply` routing + mutation-safety contract |
| `melodic-software/medley#1462` | setup-action skills self-scan: bug-report/setup, claude-ops/setup, work-items/setup, ai-briefing/setup, planning/setup + future landings (5) | **DONE** — all five backfilled; `ai-briefing/setup` and `planning/setup` caught by the scan as post-filing landings (uncovered, no family-batch owner — #1447 covers planning's seven behavior skills but not `setup`, #1457 covers ai-briefing behavior fixes not its eval — neither deferred) |

## Deferred — author in the destination repo once separation lands

Recorded as decisions, not silent omissions, each with a revisit trigger (playbook defer-record
pattern). Classifications reflect the 2026-07-15 scan; the move-out gates are preserved unchanged —
taxonomy placement did not resolve them.

- **`songwriting`** — wave map `melodic-software/medley#1369` slates songwriting for a dedicated
  personal repo, and its corpus/home is under an open decision gate (`melodic-software/medley#1402`,
  needs-human). Six of its ten skills now ship evals (`co-write`, `diagnosis`, `object-writing`,
  `rhyme`, `song-form`, `workflow`); four remain uncovered (`daily-practice`, `meter-prosody`, `setup`,
  `suno`). Authoring the remainder in the marketplace now risks migrated/wasted work. **Revisit
  trigger:** #1402 resolves songwriting's home → author the missing evals in whichever repo the plugin
  lands (evals travel with the skill dir).
- **`knowledge`** — the knowledge artifacts move to a dedicated repo (`repo(knowledge-corpus)`
  `melodic-software/medley#1393`, needs-human) and the skill set is still growing (`course-digest`
  landed pending `melodic-software/medley#1409`). `youtube` and `course-digest` now ship evals;
  `book-distill` and `setup` remain uncovered. Both the home and the skill set are unsettled, so the
  whole plugin is deferred regardless of which individual skills already carry evals. **Revisit
  trigger:** #1393 fixes the plugin's home → author the missing evals in the destination repo.

## Future coverage — setup-action skills (self-scanning batch) — 2026-07-12 record

Frozen at the 2026-07-12 stamp (pre-reorg identities); retained as program record. The setup-action
retrofits (`melodic-software/medley#1428`–`#1432`, `#1435`) ship net-new `setup`/`configure` skills
over time, and several landed *without* evals. The ideal home for a new skill's eval is the retrofit PR
that ships it — `code-tidying` #1431 did exactly this (its `setup` shipped with an eval) — but when a
retrofit ships a setup skill uncovered, the gap falls to this program. To stop chasing each landing
individually, **`melodic-software/medley#1462` is a self-scanning catch-all**: it scans
`plugins/*/skills/setup/` for any setup skill lacking `evals/evals.json` and backfills those not
already owned by a plugin-family batch (`discovery/setup` #1448, `implementation/setup` #1449,
`machine-health`/`skill-quality` setup #1454) or deferred (`knowledge`, `songwriting`). A config-writer
skill is warrantable (the `codebase-audit/setup` eval is the model). Its first pass covered
`bug-report/setup`, `claude-ops/setup`, `work-items/setup`, `ai-briefing/setup`, and `planning/setup`
(the last two caught as post-filing landings — a scaffold/dep-install setup and a
`.claude/topic-docs.yaml` concern-file writer, each with no other eval owner).

## Skip — pure-reference (2)

Knowledge-only skills; the only argument is knowledge navigation or a query, with no mutation, refusal,
or external side-effect contract to guard. Explicit skip. (The `boris` and `thariq` skills in
`playbooks` were graded pure-reference too, but each additionally ships a mutating `update` action and
is therefore warranted — both now carry evals; see the frozen #1458 row.)

| Plugin / skill | Verdict |
|---|---|
| playbooks/fable-5 | skip — pure-reference (`[full \| <chapter>]` is knowledge navigation, no mutation) |
| tdd/principles | skip — pure-reference (`[question or concept]` Q&A, no mutation) |

## Skip — hook plugins (9)

Silent-always-on components; no model-invoked skill (no `SKILL.md`). Contract tests are `.test.sh`,
not model-graded evals. Explicit skip.

`actionlint`, `bash-lint`, `biome-format`, `eol-normalizer`, `markdown-formatter`,
`powershell-format`, `ruff-format`, `desktop-notification`, `guardrails`.

## Skip — MCP-server plugins (1)

`miro` bundles a stdio MCP server (`.mcp.json` + a TypeScript/Node package) whose behavior is guarded
by the plugin's own package tests (`vitest`), not model-graded evals — the server exposes no
`SKILL.md`, so there is no per-skill behavioral contract to grade. It additionally ships a `setup`
skill, which **does** carry an eval (present per the 2026-07-15 scan). Explicit skip for the server;
the setup skill is covered.
