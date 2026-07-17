# plugin-philosophy

## Brief

### TLDR

Extend the plugin doctrine to the full current component surface (13 component types, official docs
fetched 2026-07-17), lock a native-first principle with a maturity gate, fix the topic-docs two-tier
convention's visibility seams with native mechanisms, ship a complete official-doc link index, adopt
marketplace metadata maximally — then run a fanout conformance audit of all 47 plugins whose findings
graduate to tracker-managed remediation waves.

### Goal

Every plugin measurably conforms to an extended, freshness-guarded doctrine; no custom mechanism
exists where a fitting native one does; every cross-plugin convention has exactly one registered
owner doc; the remediation program lives on the work-item tracker where any session or machine can
resume it.

### Locked decisions

| # | Decision |
|---|---|
| D1 | Deliverable = doctrine revision + fleet-consistency audit, coupled in this one Brief. CI contract-gate automation deferred to follow-on (trigger: audit reveals automatable checks). |
| D2 | Doc-link index is a first-class deliverable: every plugin-relevant official doc page linked (components mapped to their doc pages); no undocumented component types. |
| D3 | Native-first principle: prefer built-in native mechanisms (userConfig, native component types, native lifecycle events) over custom extensibility points; custom only on genuine misfit, with the misfit documented. |
| D4 | Native-adoption gate (qualifies D3): adopt a native mechanism when it (1) fills a real existing gap, (2) is stable and works cleanly — experimental/immature features wait for maturity, (3) meets repo standards. Never custom-build what a fitting native mechanism covers. |
| D5 | Cross-plugin cooperation: hybrid. Native `dependencies` reserved for hard requires (plugin genuinely broken without collaborator) — none exist today; the `{name}--v{version}` git-tag release step lands with first use. Optional collaboration stays presence-gated with documented fallbacks; artifact protocol unchanged (data handoff, which dependencies don't cover). |
| D6 | Component stance table: skills = primary surface (new frontmatter — `paths`, `context: fork`, `arguments`, skill-scoped `hooks`/`once` — adopted case-by-case); `commands/` prohibited (officially legacy); agents, MCP, LSP, output styles, `bin/` = adopt-on-need (`bin/` requires collision-safe prefixed names; doctrine notes plugin agents ignore `hooks`/`mcpServers`/`permissionMode`); plugin `settings.json` `agent` (main-thread takeover) prohibited by default, exception needs documented justification; monitors, themes, channels = wait (experimental/immature), re-verified against current docs before each audit; dependencies per D5. Hooks addition: exec-form (`args`) mandatory wherever `${user_config.*}` appears (v2.1.207), else the `CLAUDE_PLUGIN_OPTION_<KEY>` env mirror. |
| D7 | Freshness rider on all doctrine artifacts: every stance/inventory row carries a verified-date + link to its official doc page and an explicit disclaimer that the platform changes constantly — always re-fetch current docs before acting; never trust the repo file alone. |
| D8 | userConfig full-potential criterion: every personal/administrator scalar flowing through a custom channel (env-var toggle, gitignored personal file, documented hand-edit) migrates to userConfig using the full native schema — correct `type`, `default` preserving zero-config behavior, `required` only where truly blocking, `sensitive: true` for secrets, `claude plugin install --config` documented in each setup skill for headless use. Shell consumers read the native `CLAUDE_PLUGIN_OPTION_<KEY>` mirror; custom env vars retired. Ownership table otherwise unchanged. Guardrails `HOOK_<NAME>_ENABLED` toggles = flagship migration (userConfig booleans, `default: true`). |
| D9 | Setup doctrine v2: setup skill required iff (a) consumer-project config surface, (b) external prerequisites (CLI, service, credential), or (c) non-trivial userConfig — criteria applied through the modular/configurable/repo-/machine-/user-agnostic lens, never blanket ceremony; zero-config zero-prereq plugins exempt. Uniform contract: skill named `setup`, `disable-model-invocation: true`, `check` (read-only inspect/verify) + `apply` (idempotent configure) actions, complete-args non-interactive path. Formatter/linter plugins gain thin check-centric setups. Native `Setup` hook event = sanctioned headless/CI init surface; SessionStart + `${CLAUDE_PLUGIN_DATA}` manifest-diff = sanctioned runtime-dependency idiom. |
| D10 | Runtime-prerequisite visibility: anything with a runtime prereq (e.g. jq on PATH) degrades gracefully — never a hard crash; absence is surfaced to BOTH the agent and the user, with OTel as a candidate visibility channel; no black boxes. Extends the philosophy doc's "Prerequisites and failure behavior" section. |
| D11 | Convention registry: pointer-only section in PLUGIN-PHILOSOPHY.md — one owner doc per shared concern (topic-docs binding, skill layout + evals schema, `lib/hook-utils.sh` sync, report vocabularies, artifact protocol, seam phrasing); registry names and points, never restates; audit rule = per-row conformance; a new convention lands in an owner doc before a second plugin adopts it. |
| D12 | Topic-docs tiers: keep the nature-based two-tier split and the `docs/topics/` name (contents are transient topic-scoped contract docs; `docs/specs/` is already the durable vault target — renaming would conflate tiers). |
| D13 | Two-tier seam fix package (all native): R1 `worktree.baseRef: "head"` in committed repo settings so worktree-isolated spawns carry task-branch state; R2 `.worktreeinclude` with targeted memory-tier patterns (stage ledgers, EXPLORE/RESEARCH — not baselines/raw scratch; one-way creation-time copy documented); R3 pointer discipline — durable surfaces (tickets, committed PLAN) never point at prunable or gitignored paths (decompose cites the PR, not the contract path; PLAN records distilled baseline values only); R4 isolated workers return results by value, the orchestrator writes both tiers in the parent checkout; R5 the work-item tracker is the cross-lane awareness/index layer (branch files stay lane-local; markdown-in-tickets as primary artifact store rejected — not diffable, drifts from code); R6 topic-docs convention doc corrected (worktree-visibility rationale, context×tier visibility matrix, mechanisms named) — a major contract version adopted by all implementers in one wave. |
| D14 | Doc-link index: dedicated `docs/OFFICIAL-DOCS.md` — complete categorized map of plugin-relevant official pages with a component→doc-page table, per-row verified-dates, the D7 staleness disclaimer, and `https://code.claude.com/docs/llms.txt` named as the authoritative self-updating master list. CLAUDE.md keeps its lean canonical table plus one pointer row to the index. |
| D15 | Marketplace metadata maximalism (machine-, user-, org-agnostic posture): populate every helpful-signal field — `relevance` signals wherever meaningful (audit criterion per plugin), `defaultEnabled: false` for personal/niche-category plugins, `displayName` where it genuinely clarifies, complete descriptive metadata. Consumer-facing doc section on org enablement of suggestions (`pluginSuggestionMarketplaces` + source declaration in managed settings). Hard rule: `version` lives in plugin.json only, never in marketplace entries (silent-precedence trap). |
| D16 | Audit execution: doctrine docs land first; then per-plugin subagent fanout scores all 47 plugins against a doctrine-derived checklist (~15 dimensions: setup criteria, userConfig migration, exec-form hooks, metadata completeness, component stances, registry conformance, prereq degradation, pointer discipline); findings distill into a plugin×dimension conformance matrix graduating to GitHub issues — one epic + per-wave issues (setup, userConfig, metadata, hooks, convention-seam waves) via the work-items seam; raw per-plugin detail stays memory-tier; automatable checks become the deferred CI gate's backlog. |

### Constraints

- Fresh-docs mandate applies at execution time: re-fetch the relevant official pages before each edit
  wave; this Brief's doc facts were verified 2026-07-17.
- Work isolated in worktree, branch `docs/plugin-philosophy`; PRs required, squash merge, PR title
  per Conventional Commits.
- Topic-docs convention change (D13/R6) is a major contract version; every implementer plugin adopts
  in the same release wave (the contract carries no compatibility machinery).
- userConfig migrations preserve existing behavior via `default` values (guardrails toggles default
  `true`).
- Every plugin change clears the migration playbook's gate + plugin-acceptance security review.

### Acceptance criteria

- PLUGIN-PHILOSOPHY.md revised: component stance table (D6) with D7 freshness riders, native-first +
  adoption gate (D3/D4), convention registry (D11), config ownership updated (D8 criterion, exec-form
  rule, version-placement rule), setup criteria (D9), prerequisite-visibility rule (D10).
- MIGRATION-PLAYBOOK.md updated consistently (setup contract, userConfig criterion, security review
  touchpoints).
- `docs/OFFICIAL-DOCS.md` exists: complete categorized page map, component→doc table, verified-dates,
  staleness disclaimer, llms.txt master pointer; CLAUDE.md carries the pointer row and stays lean.
- Topic-docs convention doc corrected per R6 with visibility matrix; R1 settings entry, R2
  `.worktreeinclude`, and R3 skill pointer fixes (decompose ticket provenance, architect baseline
  recording) landed; the three flagged execution-time verifications resolved empirically and
  recorded.
- marketplace.json metadata complete per D15; `claude plugin validate .` passes.
- Audit epic + wave issues filed on GitHub with the conformance matrix distilled into the epic; every
  47-plugin row scored; raw details in the memory slice.
- Existing CI (plugin contract tests, markdownlint) green on every PR.

### Captured assumptions

- Consumers run CC ≥ 2.1.207 (userConfig shell-form ban semantics, pluginConfigs scoping); older
  clients degrade per official behavior, not worked around.
- Marketplace remains the melodic-software catalog but every decision holds machine-, user-, and
  org-agnostic (no solo-consumer scoping).

### Out-of-scope (deferred with triggers)

- CI contract gate — trigger: audit identifies automatable checks (D16 backlog).
- Bundle plugin (name + dependencies curated set) — trigger: one-command curated install need beyond
  the fleet-sync skill.
- Monitors, themes, channels adoption — trigger: feature exits experimental/immature status at a
  future doc re-verification (D6 wait rows).
- `music` → `creative`, deployment category, and other plugin-organization deferrals remain owned by
  that Brief.

### Deferred questions

- Windows `sensitive` userConfig storage behavior (docs silent on Windows keychain) — empirical
  verification during audit, before any secret migrates. Arbiter: `/architect` (execution evidence).
- Worktree-sweep treatment of ignored files; `--bg` session worktree base semantics;
  `worktree.baseRef` honored at project-settings scope — empirical smoke tests during D13 execution.
  Arbiter: `/architect`.
- Per-plugin `relevance` signal quality (which signals are genuinely helpful vs noise) — decided
  per-plugin during the metadata wave. Arbiter: `/architect`.

## Plan

(unfilled — /architect)
