# Extensibility-contract grading

Point-in-time grade of every shipped plugin against the extensibility contract v2.1 (the
["Extensibility contract v2.1 — the four seams"](MIGRATION-PLAYBOOK.md), convention-resolution
ladder, and setup-action sections of the [migration playbook](MIGRATION-PLAYBOOK.md)). This is an
**audit snapshot**, not durable policy — the playbook is the policy; this table records where each
plugin stood on the audit date and which follow-up issue owns each gap. Empirical claims decay: a
plugin's row is only true as of the stamp below.

> **Reconciliation — 2026-07-15 (taxonomy reorg).** The reorg renamed, split, and merged plugins
> (41 graded → 45 shipped). This pass reconciles **names and membership only — no contract grade was
> re-audited this session** (only eval *presence* was re-verified, in
> [`evals-coverage.md`](evals-coverage.md)). Surviving plugins keep their 2026-07-12 grade under the
> post-reorg name; the renames map in `.claude-plugin/marketplace.json` and the split changelogs
> (`implementation` 0.6.0, `work-items` 0.7.0, `claude-config` 0.5.0) are the authoritative old→new
> mapping. Plugins with no 2026-07-12 grade — the reorg split-offs `toolchain`, `testing`,
> `verification`, `claude-memory`, plus the never-graded `ai-briefing` — are listed under *Pending
> contract re-grade* with their contract verdict explicitly unresolved. The `playbooks` merge
> (`boris` + `thariq-skills` + `fable-5-playbook`) also warrants a class re-grade — flagged in place.

Graded 2026-07-12 against the 41 plugins in `.claude-plugin/marketplace.json` (retrofit-audit
`melodic-software/medley#1388`). Facts are Tier-0 — read from each plugin's `plugin.json`, skill
tree, and `hooks/hooks.json` this session; the MCP-carry column is the verdict from the MCP-servers
audit already codified in the playbook's ["MCP servers as a plugin component — carry
decision"](MIGRATION-PLAYBOOK.md) table (SHIP 0 / STAY 14 / DROP 0).

## Grading dimensions

- **Class** — `pure-reference` (knowledge-only skills, no config, no repo coupling),
  `hook` (ships `hooks/hooks.json`, silent-always-on, controlled by matcher / kill-switch env), or
  `behavior` (user- or model-invoked action skills).
- **Config seam** — which of the four seams the plugin exposes: `userConfig` (seam 1),
  tracked rich config `.claude/<name>.md|yaml|/**` (seam 2), consumer `CLAUDE.md`/rules only
  (seam 3), or none needed.
- **Setup action** — the contract requires *every plugin carrying a `userConfig` or tracked-config
  seam* to ship a re-runnable `setup`/`configure` action that interviews the consumer and writes the
  tracked config. Present / missing / n/a (no config seam → not required). A **config seam** is a
  file whose schema THIS plugin defines and the consumer authors to configure it (`userConfig`,
  `.claude/<plugin>.md`, `tidy-lanes/`, `songwriting/templates/`, `recurring-schedule.json`) — a
  setup action scaffolds it. Reading the consumer's **pre-existing** conventions or tool configs via
  seam 3 (`CLAUDE.md`, `REVIEW.md`, a markdownlint config, `worktree.baseRef`,
  `UBIQUITOUS-LANGUAGE.md`) is **not** a setup-requiring seam — there is nothing plugin-specific to
  write.
- **Ladder** — convention-resolution ladder compliance (config present → use; absent → infer &
  persist / ask; else safe default; no baked repo assumptions).
- **Baked repo assumptions** — hardcoded consumer layout, `melodic-software/medley` paths, or other
  source-repo coupling that survives into runtime behavior.
- **MCP-carry** — the plugin's MCP dependency and its carry verdict, per the playbook's audited
  decision table.
- **Evals** — an `evals.json` / `evaluations.md` present in the plugin.

## Verdict summary

- **No net-new work: 34 of 41.** All 9 hook plugins, all 4 pure-reference plugins, and 21 behavior
  plugins are contract-compliant as shipped (or their outstanding work is already owned by an
  existing issue).
- **Net-new setup-action gap: 7** — `bug-report`, `claude-ops`, `code-tidying`, `discovery`,
  `planning`, `songwriting`, `work-items` each expose a config seam but ship no (dedicated)
  setup action. One retrofit issue filed per plugin (linked under wave-2 map
  `melodic-software/medley#1369`). `songwriting` was reclassified from the issue's a-priori
  pure-reference expectation to behavior once graded against the evidence (9 action skills +
  a template-override seam); `work-items` carries an optional `.github/recurring-schedule.json`
  tracked seam that its per-item scaffolding does not fully substitute for a re-runnable setup.
- **Baked repo assumptions: 0.** No plugin bakes a consumer layout into runtime behavior. Four
  incidental `apps/`/`libs/`/`Platform.*` string hits are benign — test fixtures, eval-prompt
  examples, generic top-level-dir enumerations, and Claude-Code-behavior documentation — not runtime
  coupling.
- **Cross-cutting concerns owned elsewhere.** Eval coverage across all plugins is owned by the
  evals-backfill emitter `melodic-software/medley#1396` — this audit records eval presence but emits
  no eval issues. General-purpose in-repo hook migration into `guardrails`/`claude-ops` is owned by
  `melodic-software/medley#1391`. Per-slug retrofits already filed:
  `#1405` (event-storming), `#1408`/`#1409` (knowledge), `#1418` (skill-quality), `#1419`
  (machine-health), `#1420` (implementation), `#1421` (review). Current Claude Code owns
  `userConfig` prompting and persistence: knowledge, skill-quality, and machine-health setup skills
  validate the rendered value or direct the user to `/plugin configure`; none edits `pluginConfigs`.

**Membership reconciliation (2026-07-15, not a re-grade).** The reorg changed the plugin set, not the
frozen verdicts above: three pure-reference plugins (`boris`, `thariq-skills`, `fable-5-playbook`)
merged into `playbooks`; four behavior plugins were added by splits (`toolchain`, `testing`,
`verification` from `implementation`; `claude-memory` from `claude-config-audit`'s `memory-health`),
and `ai-briefing` surfaced as never graded — all five carry evals per the 2026-07-15 scan but no
contract grade (see *Pending contract re-grade*). Empirically, `setup` skills have since shipped for
most of the seven setup-action gaps below; whether each satisfies the contract is a re-audit, not done
here.

## Hook plugins (9) — compliant

Silent-always-on components: control is a `matcher` / `HOOK_<PLUGIN>_ENABLED` kill-switch, not a
`userConfig`/setup surface; project conventions arrive through the consumer's own tool-config files
(`biome.json`, `.shellcheckrc`, `.editorconfig`, …), never `CLAUDE.md`. No setup action required; no
MCP; contract tests are `.test.sh`, not evals.

| Plugin | Verdict |
|---|---|
| actionlint | compliant |
| bash-lint | compliant |
| biome-format | compliant |
| eol-normalizer | compliant |
| markdown-formatter | compliant |
| powershell-format | compliant |
| ruff-format | compliant |
| desktop-notification | compliant |
| guardrails | compliant — further in-repo hook migration into it owned by #1391 |

## Pure-reference plugins (2) — no-op

Knowledge-only skills; each README declares "no `userConfig` … pure knowledge skill". No config seam,
no hooks, no repo coupling — nothing to retrofit on the extensibility axis.

| Plugin | Verdict |
|---|---|
| playbooks | no-op grade carried from the pre-merge `boris`/`thariq-skills`/`fable-5-playbook` — **class pending re-grade**: the merge adds an `update` mutation skill, which may move the plugin from pure-reference to behavior (the extensibility no-op may still hold — it exposes no config seam) |
| tdd | no-op |

## Behavior plugins (28)

| Plugin | Config seam | Setup | Ladder | MCP-carry | Evals | Verdict / owner |
|---|---|---|---|---|---|---|
| bug-report | `userConfig` `output_dir` | **missing** | default → plugin-data | — | present | **GAP → net-new setup issue** |
| claude-ops | `userConfig` `registry_dir` + `.claude/observability/` | **missing** | default → plugin-data | ccusage (CLI-first) | absent → #1396 | **GAP → net-new setup issue** (coordinate with #1391's claude-ops telemetry seam) |
| code-tidying | tracked `.claude/tidy-lanes/**` (seam 2, folder) | **missing** | ships default lanes; consumer overrides | — | present | **GAP → net-new setup issue** (scaffold project lanes) |
| songwriting | tracked `songwriting/templates/**` override + `${CLAUDE_PROJECT_DIR}/songwriting/` output (seam 2/3) | **missing** | safe default layout + CLAUDE.md precedence; ships default templates, consumer overrides | Datamuse public API (rhyme, no secret, opt-in) | absent → #1396 | **GAP → net-new setup issue** (scaffold project template overrides). Reclassified from pure-reference: 9 action skills (`rhyme`/`co-write`/`suno`/…), not knowledge-only |
| discovery | tracked `.claude/topic-docs.yaml` (seam 2, shared concern file) | present | concern file → CLAUDE.md → infer/ask → default | perplexity/ref/microsoft-learn declared, not shipped (rule 3) | setup covered by shared convention eval | compliant |
| planning | tracked `.claude/topic-docs.yaml` (seam 2, shared concern file) | present | concern file → CLAUDE.md → infer/ask → default | — | present | compliant |
| implementation | tracked `.claude/topic-docs.yaml` (seam 2, shared concern file) + ecosystem commands | present for ecosystem commands; consumes the shared topic-docs and lifecycle artifact contracts | concern file → CLAUDE.md → infer/ask → default | — | present | compliant |
| codebase-health | tracked `.claude/codebase-health.md` (seam 2) | present | read-existing → interview → write | — | present | compliant (setup exemplar) |
| knowledge | `userConfig` `library_dir` | present | validate rendered value → `/plugin configure` when needed | — | absent → #1396 | compliant; setup never edits `pluginConfigs`; youtube/course-digest retrofits owned by #1408/#1409 |
| machine-health | `userConfig` `report_dir` + machine-local overlay | present | overlay persisted; personal scalar delegated to `/plugin configure` | — | absent → #1396 | compliant setup ownership; remaining behavior fixes owned by #1419 |
| skill-quality | `userConfig` `skills_root` | present | validate/infer candidate → `/plugin configure` when needed | — | absent → #1396 | compliant; setup never edits `pluginConfigs`; runner/contract work owned by #1418 |
| claude-config | consumer `.claude/**` via `CLAUDE_PROJECT_DIR` (seam 3) | n/a | reads consumer config | — | present | compliant |
| context7 | none needed | n/a | — | ctx7 (CLI-first) | absent → #1396 | compliant |
| firecrawl | none needed | n/a | — | firecrawl-cli (CLI-first) | absent → #1396 | compliant |
| playwright | none needed | n/a | — | @playwright/cli (CLI-first) | absent → #1396 | compliant |
| work-items | tracked `.github/recurring-schedule.json` (seam 2, optional) + backend-neutral `gh` | **partial** | `recheck` requires it; `add --recurring` scaffolds a skeleton (ask-gated); no dedicated re-runnable setup | MCP-neutral (gh CLI) | present | **GAP → net-new setup issue** (dedicated setup for the recurring schedule) |
| event-storming | none needed | n/a | — | miro STAY (degraded-but-functional) | absent → #1396 | compliant; miro reconcile owned by #1405 |
| review | tracked `.claude/topic-docs.yaml` (seam 2, shared concern file — `memory_dir`) + consumer rules (seam 3) | n/a | concern file → CLAUDE.md/rules → default | — | absent → #1396 | compliant; ecosystem-commands retrofit owned by #1421 |
| session-flow | tracked `.claude/topic-docs.yaml` (seam 2, shared concern file — `memory_dir`) | n/a | concern file → CLAUDE.md/rules → default | — | absent → #1396 | compliant |
| source-control | writes `.claude/worktrees/` (default) | n/a | safe default | — | absent → #1396 | compliant |
| debugging | none needed | n/a | — | — | absent → #1396 | compliant |
| docs-hygiene | none needed | n/a | — | — | absent → #1396 | compliant |
| architecture | none needed | n/a | — | — | present | compliant |
| mcp-tools | none needed | n/a | — | — | present | compliant |
| prototype | none needed | n/a | — | — | absent → #1396 | compliant |
| repo-hygiene | none needed | n/a | — | — | present | compliant |
| education | none needed (seam 3) | n/a | — | — | absent → #1396 | compliant |
| kindle-dedrm | none needed (own state) | n/a | — | — | absent → #1396 | compliant |

## Pending contract re-grade (added 2026-07-15)

These plugins carry no 2026-07-12 grade — four are reorg split-offs; `ai-briefing` was never graded.
Only the empirical columns below were verified this session (config-seam presence from `plugin.json`
and the skill tree, eval presence from the live scan); the contract **verdict is unresolved** pending
a re-audit against the four-seam contract. The split-offs inherit context from their source
(`toolchain`/`testing`/`verification` from `implementation`; `claude-memory` from
`claude-config-audit`) — a starting point for that audit, not a substitute for it.

| Plugin | Origin | Config seam (observed) | Setup skill | Evals | Verdict |
|---|---|---|---|---|---|
| toolchain | split from `implementation` (build, lint, setup) | `userConfig` absent; consumes the ecosystem-commands contract | present | present | **pending re-grade** |
| testing | split from `implementation` (test-\* → plan, write, e2e, diagnose) | `userConfig` absent | absent | present | **pending re-grade** |
| verification | split from `implementation` (verify-\* → confirm, measure) | `userConfig` absent | absent | present | **pending re-grade** |
| claude-memory | split from `claude-config-audit` (memory-health → health) | `userConfig` absent; reads consumer `.claude/**` (seam 3, inherited) | absent | present | **pending re-grade** |
| ai-briefing | pre-existing, never graded | `userConfig` `active_profile` (seam 1) | present | present | **pending re-grade** — a `userConfig` seam requires a setup action (present); compliance unverified |

## Net-new retrofit issues emitted

One `retrofit(<slug>)` issue per setup-action gap, sub-issue-linked under wave-2 map
`melodic-software/medley#1369`, `agent-ready`. Each is scoped to: add a re-runnable
`setup`/`configure` skill that interviews the consumer and writes the appropriate owned config
(a tracked project instruction/config file or machine-local plugin state). Personal `userConfig` is
owned by Claude Code's native plugin configuration surface; setup validates it but never writes
`pluginConfigs`. The setup remains idempotent per the playbook's
"Setup action — every configurable plugin ships one", and bump `plugin.json` `version`.

Frozen 2026-07-12 record. Per the 2026-07-15 scan, a `setup` skill dir is now present for all seven
(`bug-report`, `claude-ops`, `code-tidying`, `discovery`, `planning`, `work-items`, `songwriting`) —
the retrofit issues appear to have landed. Whether each shipped setup satisfies the contract is a
re-audit, not recorded here.

| Plugin | Issue |
|---|---|
| bug-report | melodic-software/medley#1428 |
| claude-ops | melodic-software/medley#1432 (coordinate with #1391) |
| code-tidying | melodic-software/medley#1431 |
| discovery | melodic-software/medley#1429 |
| planning | melodic-software/medley#1430 |
| songwriting | melodic-software/medley#1433 |
| work-items | melodic-software/medley#1435 |
