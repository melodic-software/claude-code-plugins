# Skill-eval coverage — warrant snapshot

Point-in-time record of which shipped skills carry model-graded evals, which *warrant* them and are
owed backfill, and which are explicit **skips**. This is an **audit snapshot**, not durable policy —
the warrant rule and the consumer-verify recipe are policy and live in the
[migration playbook](MIGRATION-PLAYBOOK.md) ("Evals — warrant policy and consumer-verify recipe").
This table records where each plugin stood on the stamp date and which backfill issue owns each gap.
Empirical claims decay: a row is only true as of the stamp below.

Stamped 2026-07-12, built from the per-skill eval presence read this session against the 42 plugins
in `.claude-plugin/marketplace.json` and the class column of
[`extensibility-contract-grading.md`](extensibility-contract-grading.md) (retrofit-audit
`melodic-software/medley#1388`, which graded 41 — the `miro` MCP-server plugin landed after that audit
and is classified below). Presence was read per-skill from each `plugins/<p>/skills/<s>/evals/evals.json`;
because sibling workers backfill concurrently, that read is accurate only at its instant — the batch
table's Status column carries the reconciliation and the live tree is the source of truth.
Emitter: evals-backfill `melodic-software/medley#1396`.

> **Live-ledger caveat.** This is a stamp-time plan in a concurrently-backfilled marketplace, not a
> live ledger. Between the stamp and any read, other workers land evals — during this document's own
> authoring, `discovery`'s `explore`/`explore-deep`/`research`/`research-deep` skills and
> `claude-config-audit/memory-health` were backfilled by sibling work. The batch issues below therefore
> instruct each author to re-check every listed skill against the live tree and **skip any that already
> ship `evals/evals.json`**. Treat the per-skill lists and counts as stamp-time identification; re-scan
> before acting.

## Warrant rule (summary)

Full rule + rationale: playbook "Evals — warrant policy and consumer-verify recipe". In brief a skill
**warrants** evals when it carries a judgment-bearing behavioral contract — triggering, routing,
refusal, or output shape that could silently regress. A skill is an explicit **skip** when it is
pure-reference (answers from a corpus, no decision contract) or a **hook** (deterministic, guarded by
`.test.sh`, no model-invoked skill). Gray-zone skills are marked **author-confirm**: the backfill
session re-checks the warrant against the live `SKILL.md` and records a skip verdict if it dissolves.

## Verdict summary

Counts below are **at stamp**; concurrent backfill has since covered many of the "owed" skills — the
batch table's Status column carries the current reconciliation, and the live tree is authoritative.

- **Covered (fully) at stamp: 7 plugins** — every behavior skill already shipped evals: `bug-report`,
  `code-tidying`, `codebase-audit`, `work-items`, `mcp-tool-audit`, `improve-architecture`,
  `repo-hygiene`.
- **Covered (partial) at stamp: 2 plugins** — `claude-config-audit` (`memory-health` was the gap, now
  backfilled) and `implementation` (`implement`, `implement-dispatch`, `build`, `lint`, `setup`
  uncovered).
- **Warranted, uncovered at stamp: 19 more plugins** — see the batch table + Status column.
- **Deferred (do not backfill in this repo now): 2 plugins** — `songwriting` and `knowledge`, each
  slated to move out of the marketplace under an open decision gate; author evals in the destination
  once separation lands.
- **Skip (explicit): 12 plugins** — 2 pure-reference + 9 hooks + 1 MCP-server (`miro`).
- **~54 warranted skills identified as uncovered** (51 at stamp + 3 setup skills that shipped uncovered
  since), grouped into **11 one-session batches** (`melodic-software/medley#1447`–`#1455`, `#1458`,
  `#1462`). Concurrent sibling backfill has since covered many; **as of the latest reconciliation ~29
  remain uncovered** (see the Status column below). The precise number keeps moving as batches land and
  new setup skills ship — the live tree, not this line, is authoritative.

## Backfill batches emitted

One issue per batch, each sized to one agent-session, sub-issue-linked under wave-2 map
`melodic-software/medley#1369`, `agent-ready`. Each batch issue carries the authoring recipe, the
schema path, and the per-skill warrant re-check instruction.

The **Status** column is the reconciliation as of the latest re-scan — `DONE` = all listed skills were
covered by concurrent sibling backfill (the issue is a no-op, close it); `PARTIAL` = some remain;
`OPEN` = none covered yet. Status decays; re-scan the tree before acting.

| Batch issue | Skills | Status (reconciled) |
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
| `melodic-software/medley#1462` | setup-action skills self-scan: bug-report/setup, claude-ops/setup, work-items/setup, ai-briefing/setup + future landings (4) | **DONE** — all four backfilled; `ai-briefing/setup` caught by the scan as a post-filing landing (uncovered, no family-batch/retrofit owner — #1457 covers behavior fixes, not its eval — not deferred) |

## Deferred — author in the destination repo once separation lands

Recorded as decisions, not silent omissions, each with a revisit trigger (playbook defer-record pattern):

- **`songwriting` (10 skills: co-write, daily-practice, diagnosis, meter-prosody, object-writing,
  rhyme, song-form, suno, workflow, and the now-shipped `setup`)** — wave map
  `melodic-software/medley#1369` slates songwriting for a
  dedicated personal repo, and its corpus/home is under an open decision gate
  (`melodic-software/medley#1402`, needs-human). Authoring 10 skills of evals in the marketplace now
  risks migrated/wasted work. **Revisit trigger:** #1402 resolves songwriting's home → author the
  evals for all 10 skills (including `setup`) in whichever repo the plugin lands (evals travel with the
  skill dir).
- **`knowledge` (book-distill, setup, and the now-shipped youtube; course-digest pending
  `melodic-software/medley#1409`)** — the knowledge artifacts move to a dedicated repo
  (`repo(knowledge-artifacts)` `melodic-software/medley#1393`, needs-human) and the skill set is still
  growing. Both the home and the skill set are unsettled, so the whole plugin is deferred regardless of
  which individual skills already carry evals (`youtube` ships one). **Revisit trigger:** #1393 fixes
  the plugin's home → author evals for whatever skills still lack them, in the destination repo.

## Future coverage — setup-action skills (self-scanning batch)

The setup-action retrofits (`melodic-software/medley#1428`–`#1432`, `#1435`) ship net-new
`setup`/`configure` skills over time, and several have landed *without* evals. The ideal home for a new
skill's eval is the retrofit PR that ships it — `code-tidying` #1431 did exactly this (its `setup`
shipped with an eval) — but when a retrofit ships a setup skill uncovered, the gap falls to this
program. To stop chasing each landing individually, **`melodic-software/medley#1462` is a self-scanning
catch-all**: it scans `plugins/*/skills/setup/` for any setup skill lacking `evals/evals.json` and
backfills those not already owned by a plugin-family batch (`discovery/setup` #1448,
`implementation/setup` #1449, `machine-health`/`skill-quality` setup #1454) or deferred (`knowledge`,
`songwriting`). A config-writer skill is warrantable (the `codebase-audit/setup` eval is the model).
Its first pass covered `bug-report/setup`, `claude-ops/setup`, `work-items/setup`, and `ai-briefing/setup`
(the last caught as a post-filing landing — a scaffold/dep-install setup with no other eval owner).

## Skip — pure-reference plugins (2)

Knowledge-only single-skill plugins; the only argument is knowledge navigation or a query, with no
mutation, refusal, or external side-effect contract to guard. Explicit skip. (`boris` and
`thariq-skills` were graded pure-reference too, but each additionally ships a mutating `update` action
and is therefore warranted — batch #1458 above.)

| Plugin / skill | Verdict |
|---|---|
| fable-5-playbook/fable-5-playbook | skip — pure-reference (`[full \| <chapter>]` is knowledge navigation, no mutation) |
| tdd/tdd | skip — pure-reference (`[question or concept]` Q&A, no mutation) |

## Skip — hook plugins (9)

Silent-always-on components; no model-invoked skill (no `SKILL.md`). Contract tests are `.test.sh`,
not model-graded evals. Explicit skip.

`actionlint`, `bash-lint`, `biome-format`, `eol-normalizer`, `markdown-formatter`,
`powershell-format`, `ruff-format`, `desktop-notification`, `guardrails`.

## Skip — MCP-server plugins (1)

Bundle a stdio MCP server (`.mcp.json` + a TypeScript/Node package), not model-invoked skills — no
`SKILL.md`, so there is no per-skill behavioral contract for a model-graded eval. Server behavior is
guarded by the plugin's own package tests (`vitest`), not evals. Explicit skip.

| Plugin | Verdict |
|---|---|
| miro | skip — MCP-server plugin, no skills (tests are `vitest`, not evals) |
