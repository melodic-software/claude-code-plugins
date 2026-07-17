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

> **Program log.** 2026-07-17: PR A (#257, Phases 1–3 + P4 evidence) squash-merged to main; all
> review findings (2 Codex inline + 2 follow-ups + 6 Claude-review) classified, fixed, and
> verified; contract slice pruned on that branch and re-committed here on `docs/topic-docs-2.0.0`
> (the PR B branch, cut from post-squash main). Next: Phase 5 wave on this branch.

Seven phases. Doctrine docs land first (D16 ordering), the topic-docs contract major version ships as
one wave, marketplace metadata follows, and the fleet audit runs last against the landed doctrine.
The fresh-docs mandate is embedded as the **first work item of every phase** that states platform
facts — never a standalone phase, never skipped.

The three flagged empirical verifications resolve at their Brief-assigned execution points:
worktree-semantics smoke tests → Phase 4 (gates Phase 5 R1/R2); per-plugin `relevance` quality →
Phase 6 (per-plugin, during the metadata wave); Windows `sensitive` userConfig storage → Phase 7
(before any userConfig-wave issue touching secrets is filed).

### Phase 1: PLUGIN-PHILOSOPHY.md doctrine revision [DONE]

Covers D3, D4, D6, D7, D8, D9, D10, D11.

Work items:

1. Fresh-fetch: `plugins`, `plugins-reference`, `skills`, `hooks`, `settings`, `plugin-dependencies`
   pages; re-verify the 13 component types and the D6 stance facts (skill frontmatter additions,
   `commands/` legacy status, `bin/` rules, agent field limitations, monitors/themes/channels
   maturity, v2.1.207 exec-form rule). Any drift from the Brief's 2026-07-17 facts is recorded in
   the memory slice and the stance table reflects current reality. The verified component-type
   count (N, expected 13) is written to `.work/plugin-philosophy/component-count.txt` — Phases 1
   and 3 sanity checks assert against N, not a hard-coded 13.
2. Add **Native-first principle + adoption gate** section (D3/D4).
3. Add **Component stance table** (D6): 13 rows, each with stance, rationale, verified-date +
   official-doc link (D7 rider), and the D7 staleness disclaimer heading the table.
4. Extend **Configuration ownership and scope**: D8 userConfig full-potential criterion (native
   schema fields, `CLAUDE_PLUGIN_OPTION_<KEY>` mirror, retirement of custom env channels), exec-form
   hooks rule, version-placement rule (`version` in plugin.json only).
5. Rewrite **Setup is explicit and repeatable** to the D9 v2 criteria (required-iff conditions,
   uniform `setup` skill contract, `Setup` hook event and SessionStart manifest-diff idioms).
6. Extend **Prerequisites and failure behavior** with D10 (graceful degradation, dual agent+user
   visibility, OTel as candidate channel, no black boxes).
7. Add **Convention registry** section (D11): pointer-only table — one owner doc per shared concern
   (topic-docs binding, skill layout + evals schema, `lib/hook-utils.sh` sync, report vocabularies,
   artifact protocol, seam phrasing); registry names and points, never restates.

**Sanity Check:**

- `grep -c "Verified 2026" docs/PLUGIN-PHILOSOPHY.md` ≥ N (one rider per stance row; N from
  `component-count.txt`).
- `grep -n "Convention registry\|Native-first" docs/PLUGIN-PHILOSOPHY.md` returns both sections.
- Component stance table row count = N; Read confirms every verified component type named.
- `npx markdownlint-cli2 --config .markdownlint-cli2.jsonc docs/PLUGIN-PHILOSOPHY.md` exit 0 (CI's
  pinned action is authoritative; local run uses the repo config).

### Phase 2: MIGRATION-PLAYBOOK.md consistency pass [DONE]

Depends on Phase 1 (doctrine wording is SSOT; playbook points, never restates).

Work items:

1. Update the per-plugin migration gate: setup-contract check (D9), userConfig criterion (D8),
   exec-form hook rule — each as a pointer to the philosophy doc section plus playbook-specific
   procedure only.
2. Extend the plugin-acceptance security review touchpoints: `sensitive` userConfig handling,
   `bin/` collision-safe naming, plugin `settings.json` `agent` prohibition check.
3. Remove or redirect any playbook text that now duplicates Phase 1 doctrine (no restated stance
   tables).

**Sanity Check:**

- `grep -n "PLUGIN-PHILOSOPHY" docs/MIGRATION-PLAYBOOK.md` shows pointer citations in the gate and
  security-review sections.
- No restated stance table: no markdown table in MIGRATION-PLAYBOOK.md whose header row contains
  both `Component` and `Stance` columns (Read assertion — pointers naming the section are fine).
- `npx markdownlint-cli2 --config .markdownlint-cli2.jsonc docs/MIGRATION-PLAYBOOK.md` exit 0.

### Phase 3: docs/OFFICIAL-DOCS.md index + CLAUDE.md pointer [DONE]

Covers D14. Parallel-safe with Phase 2 (disjoint files); component list comes from the Brief/Phase 1
stance table.

Work items:

1. Fresh-fetch `https://code.claude.com/docs/llms.txt`; enumerate every plugin-relevant page.
2. Create `docs/OFFICIAL-DOCS.md`: categorized page map, component→doc-page table, per-row
   verified-dates, D7 staleness disclaimer, llms.txt named as the authoritative self-updating
   master list.
3. Add one pointer row to CLAUDE.md's canonical table; CLAUDE.md stays lean (no other growth).
4. **Wave A join step (main session):** reconcile the component→doc table against Phase 1's
   verified component list (`component-count.txt` + stance table) before PR A — parallel work off
   the Brief snapshot must converge on Phase 1's fresh-fetched reality.

**Sanity Check:**

- `test -f docs/OFFICIAL-DOCS.md` && component table has N rows (N from `component-count.txt`).
- `grep -n "llms.txt" docs/OFFICIAL-DOCS.md` and `grep -n "OFFICIAL-DOCS" CLAUDE.md` both hit.
- CLAUDE.md diff = exactly one added table row: `git diff origin/main...HEAD --stat -- CLAUDE.md`
  shows a 1-2 line delta.
- `npx markdownlint-cli2 --config .markdownlint-cli2.jsonc docs/OFFICIAL-DOCS.md` exit 0; the
  repo's offline link-integrity check passes on the new file (external-URL lychee lane is advisory
  weekly — spot-check a sample of new URLs via WebFetch instead).

### Phase 4: Worktree-semantics empirical verification (throwaway spike) [DONE]

Feasibility spike (might change Phase 5's shape) — results are evidence, no kept code. Parallel-safe
with Phases 1–3 (touches scratchpad + throwaway worktrees only).

All tests run in a **throwaway `git init` repo in the scratchpad with a synthetic `origin`** —
never in this repo (its ~30 live worktrees, runtime-written `.git/info/exclude`, and main checkout
on a feature branch confound every measurement). Use `claude -p --worktree` exclusively (skips the
trust dialog; interactive mode errors in a fresh repo). Unique worktree names per run (name reuse
resets clean worktrees to base since v2.1.208); the spike removes its own worktrees
(`-p`-created worktrees are never auto-cleaned; Windows: expect NTFS lock retries,
`git worktree remove --force`).

Work items:

1. Fresh-fetch the `worktrees` doc (the doc anchor for `baseRef`/`.worktreeinclude` — not the
   settings page) plus `settings`; record cited behavior, including the documented fallback
   "when `origin/HEAD` isn't resolvable, worktrees fall back to current local HEAD".
2. Smoke test A — `worktree.baseRef: "head"` at **project-settings scope**, two arms: **control**
   (`baseRef` unset or `"fresh"`) asserts marker ABSENT; **treatment** (`baseRef: "head"` in
   committed `.claude/settings.json`) asserts marker PRESENT. Verdict HONORED only if BOTH arms
   behave — a marker-present-only test is defeated by the documented origin/HEAD fallback (false
   positive). Variant A2: spawn from within an existing linked worktree (docs state `head` resolves
   to that worktree's HEAD — test against that expected value). Variant A3: `settings.json` present
   only in the worktree checkout vs only in the main checkout — pins which copy a linked-worktree
   session reads (undocumented; only `settings.local.json` is documented as main-checkout-resolved).
3. Smoke test B — `.worktreeinclude` one-way creation-time copy: use real nested-gitignore paths
   (`.work/<slug>/…` ignored via a nested `*` `.gitignore`, mirroring this repo) — not a toy
   root-level pattern; assert copy at creation; modify original, assert no sync-back.
4. Smoke test C — worktree-sweep treatment of ignored files (genuinely undocumented — this test is
   the only source of truth; capture `git status --ignored` snapshots in the raw transcript) +
   `--bg` session worktree base semantics.
5. The sub-agent records raw transcripts in `.work/plugin-philosophy/verifications/`, stamps every
   VERDICT file with `claude --version`, and **returns the VERDICT lines by value**; the **main
   session** fills the pending rows in this PLAN's "Empirical verification results" table (PLAN.md
   edits stay main-session-only) and feeds them into Phase 5's R1/R2 design. If the CC version has
   moved by the Phase 5 gate, re-run the cheap test-A control/treatment pair.

**Sanity Check:**

- `.work/plugin-philosophy/verifications/` contains ≥ 3 result files, one per smoke test, each
  ending in a one-line VERDICT (`HONORED` / `NOT-HONORED` / behavior description) and a
  `claude --version` stamp line.
- Test A result file contains BOTH `control:` and `treatment:` lines with opposite marker outcomes
  (else verdict is invalid by construction).
- This PLAN's "Empirical verification results" table row 1 is filled (no `(pending)`).

### Phase 5: Topic-docs contract 2.0.0 + seam fixes R1–R6 (one wave) [TODO]

Covers D13. Contract-major change: every implementer adopts in the same wave (no compatibility
machinery). Gated by Phase 4 verdicts.

Work items:

1. **Pre-flight consumer check (first item):** `Grep`/`Glob` for every consumer parsing the
   convention surface — `.claude/topic-docs.yaml` keys, slug spec, tier paths, runtime guards, the
   `scripts/check-cross-plugin-source-drift.sh` registry, hooks reading `docs/topics/` or `.work/`.
   Document parse paths in the memory slice before editing anything.
2. R6 — rewrite `docs/conventions/topic-docs/README.md`: worktree-visibility rationale, context ×
   tier visibility matrix, native mechanisms named (`worktree.baseRef`, `.worktreeinclude`, by-value
   returns, tracker index); CHANGELOG entry `2.0.0`; schema untouched unless a key changes (KEEP
   expected). **Reconcile the Implementers table with reality**: `toolchain` and `verification`
   carry `reference/topic-docs.md` but are absent from the table; `knowledge`, `claude-ops`,
   `docs-hygiene` are listed without delta docs — the 2.0.0 table must match the actual fleet
   (add/annotate rows or document why a row is delta-doc-free). The CHANGELOG 2.0.0 entry states
   the **mixed-fleet window** and why it is safe (no tier/key/slug-spec change — installed cache
   copies and in-flight branches keep 1.x text until they update; divergence is doctrinal, not
   layout-corrupting), and notes a post-PR-B stale-text sweep obligation for in-flight branches at
   their merge time.
3. R1 — committed `.claude/settings.json` with `worktree.baseRef: "head"` (shape per Phase 4 smoke
   test A verdict; if NOT-HONORED at project scope, execute the tagged fallback below). Rollout
   note in the PR B description + convention doc: a clone with an existing untracked
   `.claude/settings.json` hits "untracked working tree file would be overwritten" on pull —
   document the remedy; state the repo-wide worktree-spawn behavior change; **gitignore
   `.claude/worktrees/` in the same change** (mandatory — the runtime `.git/info/exclude` entry is
   machine-local; CI checkouts and fresh clones lack it, and partial tracking of `.claude/`
   otherwise turns nested worktrees into `git add -A` hazards); run the hygiene CI lanes
   (machine-specific-paths, gitleaks, editorconfig) locally on the new tracked file. Document the
   escape hatch: a personal `.claude/settings.local.json` (main-checkout-resolved, covers every
   worktree) silently overrides R1 machine-wide — the convention doc states this; no audit
   dimension may assume R1 is universally in force.
   **Consumer-adoption path (mandatory):** repo settings never travel with marketplace-installed
   plugins (isolated cache) — R1/R2 as files fix only this repo. The 2.0.0 doc ships a
   consumer-adoption section: the settings snippet + a `.worktreeinclude` template, scoped as
   "authoring-repo materialization; consumer repos self-apply" (routing it through a D9 setup-skill
   `apply` action is recorded as a follow-on trigger, not built now). The visibility matrix gains a
   caveat row: a `WorktreeCreate` hook makes `.worktreeinclude` inert (documented) — hook script
   owns the copy.
4. R2 — `.worktreeinclude` with targeted memory-tier patterns (stage ledgers, EXPLORE/RESEARCH; not
   baselines/raw scratch); one-way creation-time copy documented in the convention doc.
5. R3 — pointer-discipline fixes: `plugins/work-items/skills/decompose` cites the PR (not contract
   paths) in ticket provenance; `plugins/planning/skills/architect` records distilled baseline
   values in PLAN (raw captures stay memory-tier). Sweep both skill bodies for prunable-path
   citations.
6. R4/R5 — convention doc text: isolated workers return results by value with the orchestrator
   writing both tiers in the parent checkout (R4); the work-item tracker named as the cross-lane
   awareness/index layer, markdown-in-tickets rejected with rationale (R5).
7. Implementer wave: update all 8 `plugins/*/reference/topic-docs.md` delta docs against the 2.0.0
   owner doc; bump each touched plugin's `plugin.json` semver + CHANGELOG; docs-hygiene declutter
   detector references checked (reader row).

File inventory (checkbox discipline — tick as processed):

| File | Action | Rationale |
|---|---|---|
| [ ] `docs/conventions/topic-docs/README.md` | MODIFY | R6 rewrite, visibility matrix, R4/R5 text |
| [ ] `docs/conventions/topic-docs/CHANGELOG.md` | MODIFY | 2.0.0 entry |
| [ ] `docs/conventions/topic-docs/topic-docs.schema.json` | KEEP (audit) | no key changes expected |
| [ ] `docs/conventions/topic-docs/examples/*` | AUDIT | update only if matrix/mechanisms change examples |
| [ ] `.claude/settings.json` | CREATE | R1 `worktree.baseRef` |
| [ ] `.worktreeinclude` | CREATE | R2 patterns |
| [ ] `plugins/discovery/reference/topic-docs.md` | MODIFY | 2.0.0 adoption |
| [ ] `plugins/implementation/reference/topic-docs.md` | MODIFY | 2.0.0 adoption |
| [ ] `plugins/planning/reference/topic-docs.md` | MODIFY | 2.0.0 adoption |
| [ ] `plugins/review/reference/topic-docs.md` | MODIFY | 2.0.0 adoption |
| [ ] `plugins/session-flow/reference/topic-docs.md` | MODIFY | 2.0.0 adoption |
| [ ] `plugins/toolchain/reference/topic-docs.md` | MODIFY | 2.0.0 adoption |
| [ ] `plugins/verification/reference/topic-docs.md` | MODIFY | 2.0.0 adoption |
| [ ] `plugins/work-items/reference/topic-docs.md` | MODIFY | 2.0.0 adoption |
| [ ] `plugins/work-items/skills/decompose/SKILL.md` | MODIFY | R3 ticket provenance |
| [ ] `plugins/planning/skills/architect/SKILL.md` | MODIFY | R3 baseline recording |
| [ ] 8–10 × `plugins/*/plugin.json` + `CHANGELOG.md` | MODIFY | semver bump per touched plugin |
| [ ] `plugins/knowledge/…`, `plugins/claude-ops/…`, `plugins/docs-hygiene/…` | AUDIT | implementer-table rows without delta docs — verify no stale convention text |

**Sanity Check:**

- `bash scripts/check-cross-plugin-source-drift.sh --check` exit 0 (the flag CI runs; flagless mode
  is informational only).
- `grep -n "2.0.0" docs/conventions/topic-docs/CHANGELOG.md` hits; `grep -rn "visibility matrix" -i
  docs/conventions/topic-docs/README.md` hits.
- Implementers-table parity: every `plugins/*/reference/topic-docs.md` path has a matching table
  row and vice versa (Read assertion against the glob result).
- Pre-flight consumer list exists: `.work/plugin-philosophy/consumers-topic-docs.md` non-empty.
- Every plugin with a modified file has a `plugin.json` version bump:
  `git diff origin/main...HEAD --name-only | grep '^plugins/' | cut -d/ -f2 | sort -u` each has a
  matching `plugins/<name>/plugin.json` in the diff.
- `bash scripts/validate-plugins.sh` exit 0 (includes `generate-catalog.mjs --check` — regenerate
  the catalog if any plugin.json description changed).
- `npx markdownlint-cli2 --config .markdownlint-cli2.jsonc` on touched .md files exit 0.

### Phase 6: Marketplace metadata wave [TODO]

Covers D15 + per-plugin `relevance` quality verification (deferred question c).

Work items:

1. Fresh-fetch `plugin-marketplaces` + `discover-plugins` + `plugins-reference`
   (default-enablement section) + the dedicated `plugin-relevance` page; re-verify entry schema
   (`relevance`, `defaultEnabled`, `displayName`, description precedence, `version`
   silent-precedence trap). **`defaultEnabled` flip semantics for already-installed consumers are
   undocumented** — if the fetched pages stay silent, run a 2-minute empirical flip on one plugin
   before the wave (does a marketplace refresh disable an existing install?). Never touch a
   plugin's `name` (breaks existing installs without a `renames` map); `displayName` is safe.
2. Per-plugin pass over all 47 entries: add `relevance` only where the signal is genuinely helpful
   (judged per-plugin — noise rejected), `defaultEnabled: false` for personal/niche categories,
   `displayName` where it clarifies, complete descriptions; assert **no `version` field in any
   entry**.
3. Consumer-facing doc section on org enablement of suggestions (`pluginSuggestionMarketplaces` +
   managed-settings source declaration) — lands in the discover/consumer section of README or
   OFFICIAL-DOCS per where consumer docs live (decided at execution against the fetched page).
4. Record per-plugin relevance decisions (adopted vs rejected-as-noise) in
   `.work/plugin-philosophy/relevance-decisions.md`.
5. Regenerate the README catalog: `node scripts/generate-catalog.mjs` (CI runs `--check`; metadata
   edits drift the generated block otherwise).

**Sanity Check:**

- `claude plugin validate .` exit 0.
- `node scripts/generate-catalog.mjs --check` exit 0.
- `node -e` assertion: 47 entries; every entry resolves a description (entry or plugin.json);
  `version` absent from all entries — exit 0.
- `.work/plugin-philosophy/relevance-decisions.md` has 47 rows.

### Phase 7: Fleet conformance audit fanout + tracker graduation [TODO]

Covers D16. Runs against merged doctrine (Phases 1–6 landed).

Work items:

1. **Search-before-create (first item):** `gh issue list --search` for an existing
   plugin-conformance epic / wave issues. Match found → pivot to updating the existing items
   (record the match + pivot in the memory slice); no match → proceed to create. Verify required
   labels exist (`gh label list`) and create missing ones before any `gh issue create --label`
   call (missing labels fail the create).
2. Derive the audit checklist (~15 dimensions) from the landed doctrine docs: setup criteria (D9),
   userConfig migration (D8), exec-form hooks, metadata completeness (D15), component stances (D6),
   registry conformance (D11), prereq degradation (D10), pointer discipline (R3), freshness riders
   (D7), plus dimensions the doctrine text yields. **Freeze a rubric file** with per-dimension
   anchored PASS/FAIL criteria + one worked example, injected verbatim into every worker prompt
   (uncalibrated independent scoring across batches encodes rubric drift, not conformance).
   **Authority rule:** plugins are scored against **landed doctrine only**; where a fresh-fetched
   doc disagrees with doctrine, that is a doctrine-update finding (its own wave), never plugin
   nonconformance. Dimensions may not assume R1 is universally in force (local-settings override
   exists). Checklist + rubric → memory slice.
3. Fresh-fetch the component doc pages the checklist cites (to detect doctrine-vs-platform drift
   per the authority rule above).
4. **Windows `sensitive` userConfig empirical verification** (deferred question a): configure a
   throwaway `sensitive` userConfig value on this Windows machine; locate where it persists
   (Credential Manager vs plaintext file); VERDICT recorded before any userConfig wave issue
   involving secrets is filed. Secrets excluded from that wave if storage is plaintext (tagged
   fallback below).
5. Fanout: **pilot batch of 3–5 plugins first**, reviewed by the main session against the rubric
   before full fanout; then per-plugin subagents score the remainder in **batches of 8–10**; each
   worker writes its own raw report to `.work/plugin-philosophy/audit/<plugin>.md` (memory-tier
   raw output is carved out of R4 — R4's orchestrator-writes rule governs contract/durable tiers)
   and returns only its scored dimension row by value; the orchestrator (main session) appends
   matrix rows incrementally per batch, so a compaction mid-run loses nothing. **Double-score a
   random 3-plugin sample** with independent workers and reconcile disagreements before graduating
   the matrix.
6. File the GitHub epic (conformance matrix distilled inline — **single-token score cells only**,
   prose lives in per-wave issues; GitHub bodies cap near 64 KB) + per-wave issues (setup,
   userConfig, metadata, hooks, convention-seam) via the work-items seam; issues cite the epic + PR
   permalinks, never contract/memory paths (R3). Automatable checks list → epic section = deferred
   CI gate backlog (D1 trigger).

**Sanity Check:**

- Search outcome recorded: `.work/plugin-philosophy/audit/tracker-search.md` states the query + hit
  count + create-vs-update decision.
- `ls .work/plugin-philosophy/audit/*.md | wc -l` ≥ 47 (one report per plugin) + matrix file with
  47 scored rows.
- `gh issue list --label epic --search "plugin conformance"` (or equivalent) returns the epic;
  epic body contains the matrix; ≥ 5 wave issues reference the epic.
- `grep -c "docs/topics/\|\.work/" <epic and wave issue bodies>` = 0 (pointer discipline).
- Windows `sensitive` VERDICT file exists in `.work/plugin-philosophy/verifications/`.

### Empirical verification results

| # | Question | Phase | VERDICT |
|---|---|---|---|
| 1 | `worktree.baseRef` at project scope; sweep of ignored files; `--bg` base | 4 | HONORED (CC 2.1.212, control+treatment): committed project `.claude/settings.json` `worktree.baseRef: "head"` honored, incl. from linked worktrees (A2: resolves to the worktree's own HEAD; A3: a linked-worktree session reads its OWN checkout's settings.json). `.worktreeinclude`: nested-gitignored files qualify, copy is one-way creation-time. Sweep: `--worktree` worktrees never auto-swept (empirical); subagent/bg sweep would remove ignored-only worktrees (INFERRED — ignored ≠ untracked). `--bg` base = origin/HEAD by default, so R1 moves it to local HEAD. Windows caveat: deep worktree base paths can trip git PATH_MAX (`'$GIT_DIR' too big`); this repo's base (~95 chars) is safe. |
| 2 | Per-plugin `relevance` signal quality | 6 | (pending — per-plugin ledger) |
| 3 | Windows `sensitive` userConfig storage | 7 | (pending) |

## Blast radius

**HIGH.** Matches stress-test triggers: new conventions constraining all future work (doctrine +
contract-major), architecture decisions across 47 plugins + 8 implementer materializations, shared
committed settings (`.claude/settings.json`) affecting every session, and undocumented behavior
(worktree semantics, Windows sensitive storage — mitigated by the empirical phases). Reversible via
git revert (docs/metadata only, no runtime code), and existing CI (contract tests, markdownlint,
drift check) gates every PR — hence HIGH, not CRITICAL.

## Stress-test summary

Two fresh-context adversarial passes ran; all findings verified against the repo before adoption.

**Plan-reviewer (Step 3):** 9 IMPORTANT + 5 SUGGESTION, 0 CRITICAL — all applied: implementer-roster
reconciliation + parity check (Phase 5), CI-parity sanity commands (drift `--check`, catalog
`--check`, markdownlint config, `node -e` over Python), pointer-vs-restate check made structural
(Phase 2), Phase 4 by-value/fence contradiction resolved, component-count made variable with a
Wave A join step, PR-chain PLAN lifecycle defined, Phase 7 batching + label verify-or-create,
worktree-variant smoke tests, R1 rollout notes.

**Devils-advocate (Step 4):** 16 assumptions attacked; 4 mandatory changes, all applied:
(1) Phase 4 redesigned — isolated scratch repo with synthetic origin, control+treatment arms
(defeats the documented origin/HEAD-fallback false positive), settings-scope variant A3,
CC-version-stamped verdicts with re-run at the Phase 5 gate; (2) PLAN lifecycle switched to
branch-local prune-per-PR (the program must not self-violate the contract it ships); (3) 2.0.0 doc
gains a consumer-adoption path — repo settings provably never reach marketplace-installed
consumers; (4) Phase 7 calibration — frozen anchored rubric, pilot batch, double-scored sample.
Also adopted: mandatory `.claude/worktrees/` gitignore in PR B, `WorktreeCreate`-hook caveat for
`.worktreeinclude`, mixed-fleet window statement in the CHANGELOG, doctrine-wins authority rule for
audit scoring, `defaultEnabled`-flip empirical check, matrix cell budget (64 KB body cap), `name`
immutability during the metadata wave. One finding escalated to a user gate: R6 major-vs-minor
contradiction with the contract's own versioning rule (see User-approval gates).

## Execution shape

Two parallel-safe waves inside an otherwise sequential PR chain; fanout inside Phase 7.

| Phase | Surface | Basis |
|---|---|---|
| 1 | Main session | Judgment-heavy doctrine writing; SSOT wording others depend on |
| 2 | Main session | Depends on Phase 1 wording; pointer discipline needs judgment |
| 3 | Sub-agent worker (parallel with 1–2) | Mechanical index build from llms.txt; disjoint files (`OFFICIAL-DOCS.md`, one CLAUDE.md row) |
| 4 | Sub-agent worker (parallel with 1–3) | Scripted smoke tests; touches scratch/throwaway worktrees only |
| 5 | Main session (implementer sweep may fan out mechanically) | Contract-major judgment; 25-file wave needs single editorial voice |
| 6 | Main session | Single file; 47 per-plugin relevance judgments |
| 7 | Workflow/sub-agent fanout, orchestrated by main session | D16-locked fanout; R4 by-value returns |

Wave A (parallel): Phase 1 (main) ∥ Phase 3 (sub-agent) ∥ Phase 4 (sub-agent). Zero file overlap:
P1 = `docs/PLUGIN-PHILOSOPHY.md`; P3 = `docs/OFFICIAL-DOCS.md` + CLAUDE.md; P4 = `.work/` + scratch.
Wave B (sequential): Phase 2 → Phase 5 → Phase 6 → Phase 7.

Scope fences (Wave A): P3 agent ALLOWED `docs/OFFICIAL-DOCS.md`, `CLAUDE.md` (one row);
FORBIDDEN everything else incl. PLAN.md. P4 agent ALLOWED `.work/plugin-philosophy/verifications/`
and throwaway `git init` repos under the scratchpad (its own branches/worktrees live there);
FORBIDDEN every file and branch of THIS repo (note: `claude -p --worktree <name>` creates branches
named `worktree-<name>` — another reason the spike never runs in this repo).
Sequential fallback: any fence violation or agent failure → that phase re-runs inline main-session
in Wave B order. PLAN.md edits are main-session-only.

Cost note: Wave A = 2 extra agents vs sequential (~saves one serial doc-build + smoke-test round);
Phase 7 = ~47 scoring agents (D16-locked, run regardless of shape).

## Open questions

None blocking — the three empirical questions are scheduled inside phases with tagged fallbacks.

## Handoff to implementation

### User-approval gates

- **[BRIEF CONTRADICTION — user decision required]** D13 locks R6 as a **major** contract version
  ("2.0.0, one wave"), but the contract's own Versioning rule says major = "moves a tier, renames a
  key, or alters the slug spec" — R6 does none (schema KEEP; the change is visibility semantics +
  doctrine text). Options: (a) keep 2.0.0 and amend the Versioning rule so visibility-semantics
  guarantees also count as major (the doctrine repo then applies its own rule consistently);
  (b) downgrade to a 1.x minor, dissolving the one-wave coordination burden and most of Phase 5's
  mixed-fleet risk. RECOMMENDED: (a) — the Brief locked the one-wave clean break deliberately, and
  a visibility-guarantee change does alter what implementers may rely on; the rule amendment makes
  the label honest. The plan as written assumes (a).
- [FALLBACK — confirm or override] Smoke test A fails (project-scope `worktree.baseRef` not
  honored): R1 degrades to documenting the limitation + the strongest honored scope in the
  convention doc, and an upstream issue is filed; R2/R6 proceed unchanged.
- [FALLBACK — confirm or override] Windows `sensitive` storage is plaintext: secret-bearing
  userConfig migrations are excluded from the userConfig wave issue and recorded as blocked-upstream
  in the epic; non-secret migrations proceed.
- Scope-expansion of any kind (new convention, new component adoption) mid-flight → stop and ask.

### Execution shape ([EXEC-SHAPE] tagged)

- [EXEC-SHAPE] PR slicing: PR A = Phases 1–3 (doctrine + index, current branch
  `docs/plugin-philosophy`); PR B = Phases 4–5 (contract 2.0.0 wave; Phase 4 evidence rides the
  memory tier, distilled results in PLAN); PR C = Phase 6 (metadata); PR D = close-out (Phase 7's
  PLAN/verdict updates + prune-with-pointer). Rationale: reviewability + distinct concerns
  (doctrine vs contract-major vs metadata); each PR independently green on existing CI.
- [EXEC-SHAPE] PLAN.md lifecycle across the PR chain — **branch-local, prune-per-PR**: the
  topic-docs contract says contract slices are pruned before merge, and this program (which ships
  that very contract's 2.0.0) must not self-violate by parking a slice on `main` for weeks. Each PR
  branch commits the current PLAN, pastes it into its PR description, and prunes the slice in a
  final commit before merge; the next PR branch (cut from post-squash `main`) re-commits the
  updated PLAN from the local working tree. Cross-PR continuity = the PR-description pastes + (from
  Phase 7) the epic. Close-out at PR D: Phase 7's verdict rows and final status tags commit there,
  durable outcomes graduate, final prune-with-pointer. The Windows `sensitive` VERDICT is recorded
  durably (PLAN verdict table → PR D description + epic), not only in gitignored `.work/`.
  (Alternative rejected: adding a multi-PR-program exception clause to the 2.0.0 lifecycle text —
  viable, but it lands only in PR B while PR A would already need it; override at approval if the
  exception clause is preferred.)
- [EXEC-SHAPE] Wave A parallelism + fences as tabled above.
- [EXEC-SHAPE] Phase 7 fanout surface: per-plugin subagents (Workflow engine if available, plain
  sub-agent fanout otherwise) — D16 locks the fanout itself.
- [EXEC-SHAPE] Empirical verifications embedded at Brief-assigned execution points (P4/P6/P7)
  rather than a standalone verification phase.

### Mechanical work

- Commit boundaries: one commit per phase minimum; Phase 5 = one wave commit for the contract bump +
  implementer adoption (clean break lands atomically); PLAN.md status-tag updates ride each phase's
  commit. Each PR branch is cut from **post-squash `main`**, never from the previous PR branch
  (stacking would replay the prior PR's squashed commits in the diff).
- Verification checkpoints: run each phase's Sanity Check before its commit; existing CI
  (contract tests, markdownlint, drift check) green before each PR merge.
- Sequential fallback: documented under Execution shape; orchestrator-writes rule (R4) applies to
  all fanout output.
- Close-out: `/architect close-out` at PR time — PLAN.md into PR description `<details>`, durable
  outcomes graduate (vault_backend `docs`), contract slice pruned with pointer.
