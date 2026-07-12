# Skill-eval coverage — warrant snapshot

Point-in-time record of which shipped skills carry model-graded evals, which *warrant* them and are
owed backfill, and which are explicit **skips**. This is an **audit snapshot**, not durable policy —
the warrant rule and the consumer-verify recipe are policy and live in the
[migration playbook](MIGRATION-PLAYBOOK.md) ("Evals — warrant policy and consumer-verify recipe").
This table records where each plugin stood on the stamp date and which backfill issue owns each gap.
Empirical claims decay: a row is only true as of the stamp below.

Stamped 2026-07-12, built from the per-skill eval presence read this session against the 41 plugins
in `.claude-plugin/marketplace.json` and the class column of
[`extensibility-contract-grading.md`](extensibility-contract-grading.md) (retrofit-audit
`melodic-software/medley#1388`). Facts are Tier-0 — presence read from each `plugins/<p>/skills/<s>/evals/evals.json`.
Emitter: evals-backfill `melodic-software/medley#1396`.

## Warrant rule (summary)

Full rule + rationale: playbook "Evals — warrant policy and consumer-verify recipe". In brief a skill
**warrants** evals when it carries a judgment-bearing behavioral contract — triggering, routing,
refusal, or output shape that could silently regress. A skill is an explicit **skip** when it is
pure-reference (answers from a corpus, no decision contract) or a **hook** (deterministic, guarded by
`.test.sh`, no model-invoked skill). Gray-zone skills are marked **author-confirm**: the backfill
session re-checks the warrant against the live `SKILL.md` and records a skip verdict if it dissolves.

## Verdict summary

- **Covered (fully): 7 plugins** — every behavior skill already ships evals: `bug-report`,
  `code-tidying`, `codebase-audit`, `work-items`, `mcp-tool-audit`, `improve-architecture`,
  `repo-hygiene`.
- **Covered (partial) → backfill owed: 2 plugins** — `claude-config-audit` (2/3;
  `memory-health` uncovered) and `implementation` (6/11; `implement`, `implement-dispatch`, `build`,
  `lint`, `setup` uncovered).
- **Warranted, uncovered → backfill owed: 15 more plugins** — see the batch table.
- **Deferred (do not backfill in this repo now): 2 plugins** — `songwriting` and `knowledge`, each
  slated to move out of the marketplace under an open decision gate; author evals in the destination
  once separation lands.
- **Skip (explicit): 13 plugins** — 4 pure-reference + 9 hooks.
- Total warranted skills owed backfill this wave: **46**, grouped into **8 one-session batches**
  (`melodic-software/medley#1447`–`#1454`).

## Backfill batches emitted

One issue per batch, each sized to one agent-session, sub-issue-linked under wave-2 map
`melodic-software/medley#1369`, `agent-ready`. Each batch issue carries the authoring recipe, the
schema path, and the per-skill warrant re-check instruction.

| Batch issue | Skills | Notes |
|---|---|---|
| `melodic-software/medley#1447` | planning: architect, brainstorm, design, design-handoff, devils-advocate, interview, prd (7) | — |
| `melodic-software/medley#1448` | discovery: explore, explore-deep, research, research-deep; claude-config-audit: memory-health (5) | closes the claude-config-audit partial gap |
| `melodic-software/medley#1449` | implementation: implement, implement-dispatch, build, lint, setup (5) | #1420 (ecosystem-commands + setup) CLOSED → stable; build/lint/setup author-confirm |
| `melodic-software/medley#1450` | docs-hygiene: compress, declutter, encapsulation-audit, extract-ssot, rename-references (5) | — |
| `melodic-software/medley#1451` | session-flow: handoff, orchestration-brief, retro, workflow; source-control: commit, pull-request, worktree (7) | — |
| `melodic-software/medley#1452` | claude-ops: claude-code-changelog, claude-observability, claude-troubleshooting; prototype: logic, ui (5) | coordinate w/ claude-ops setup #1432 + hook migration #1391 (no file conflict) |
| `melodic-software/medley#1453` | context7, firecrawl, playwright, diagnose, teach, kindle-dedrm (6) | thin single-skill plugins; proportional case counts |
| `melodic-software/medley#1454` | event-storming: methodology, simulation; machine-health: machine-health, setup; skill-quality: skill-quality, setup (6) | author vs current shipped behavior; owning retrofits update their eval on behavior change — simulation #1405, machine-health #1419, skill-quality #1418 |

## Deferred — author in the destination repo once separation lands

Recorded as decisions, not silent omissions, each with a revisit trigger (playbook defer-record pattern):

- **`songwriting` (9 skills: co-write, daily-practice, diagnosis, meter-prosody, object-writing,
  rhyme, song-form, suno, workflow)** — wave map `melodic-software/medley#1369` slates songwriting for a
  dedicated personal repo, and its corpus/home is under an open decision gate
  (`melodic-software/medley#1402`, needs-human). Authoring 9 skills of evals in the marketplace now
  risks migrated/wasted work. **Revisit trigger:** #1402 resolves songwriting's home → author the
  evals in whichever repo the plugin lands (evals travel with the skill dir).
- **`knowledge` (2 shipped skills: book-distill, setup; + youtube/course-digest pending)** — the
  knowledge artifacts move to a dedicated repo (`repo(knowledge-artifacts)`
  `melodic-software/medley#1393`, needs-human) and the skill set is still growing (youtube #1408 /
  course-digest #1409, needs-decision). Both the home and the skill set are unsettled. **Revisit
  trigger:** #1393 fixes the plugin's home AND #1408/#1409 land the new skills → author evals for the
  full stable skill set in the destination.

## Future coverage — net-new skills not yet shipped

The seven setup-action retrofits (`melodic-software/medley#1428`–`#1432`, `#1433`, `#1435`) each add a
net-new `setup`/`configure` skill that does not exist yet. When each setup skill lands, add a setup
eval for it (the `codebase-audit/setup` eval is the model — a config-writer skill is warrantable).
This is a per-retrofit follow-on, not part of the backfill batches above.

## Skip — pure-reference plugins (4)

Knowledge-only single-skill plugins; no decision/routing/refusal contract to guard. Explicit skip.

| Plugin / skill | Verdict |
|---|---|
| boris/boris | skip — pure-reference |
| fable-5-playbook/fable-5-playbook | skip — pure-reference |
| thariq-skills/thariq-skills | skip — pure-reference |
| tdd/tdd | skip — pure-reference |

## Skip — hook plugins (9)

Silent-always-on components; no model-invoked skill (no `SKILL.md`). Contract tests are `.test.sh`,
not model-graded evals. Explicit skip.

`actionlint`, `bash-lint`, `biome-format`, `eol-normalizer`, `markdown-formatter`,
`powershell-format`, `ruff-format`, `desktop-notification`, `guardrails`.
