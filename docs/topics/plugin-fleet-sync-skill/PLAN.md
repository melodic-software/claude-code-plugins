# plugin-fleet-sync-skill

## Brief

### TLDR

Add `/claude-ops:plugins` — an action-routed skill that deterministically brings a machine's plugin fleet current on demand: marketplace refresh, update of the *effective* (actually-loaded) scopes, policy-driven install of new catalog plugins, scope-divergence detection, and explicit scope convergence — with a terse actionable report.

### Goal

One command that guarantees, on any machine and from any directory, that the plugins which actually load are the latest published versions of everything the marketplace offers, and that surfaces (never silently fixes) any state where something older or unintended is what really runs.

### Decisions (locked)

1. **Marketplace scope**: defaults to the marketplace this plugin was installed from, resolved dynamically (never hardcoded). Optional `<marketplace>` or `all` argument extends the same loop.
2. **Home**: `claude-ops` plugin (Claude Code operational tooling). No marketplace.json edit needed; bump plugin.json version + CHANGELOG + README + description.
3. **Surface**: skill `plugins`, action router — `sync` (default, mutating), `audit` (read-only dry-run of everything sync/converge would do), `converge` (explicit scope consolidation). Mirrors the `changelog` skill's router shape.
4. **Sync semantics — "effective fleet current where you stand"**:
   - Always: `claude plugin marketplace update <name>` (self-heals corrupt clones: pull failure → automatic re-clone), then per-plugin `claude plugin update` sweep at user scope, then install-new per policy, then enabledPlugins completeness check.
   - Inside a project with project/local-scope installs: additionally update those installs in place (`plugin update -s project|local`) — they are what loads there.
   - Ends with reload guidance (see deferred: `--force`).
5. **Install policy**: `install_new` userConfig scalar — `ask` (default; new catalog plugins offered in one batched multi-select prompt) | `all` | `none`.
6. **Converge** (only committed-settings-touching action): detects any plugin id with >1 scope entry (divergent version or enable state), previews per-plugin intent, confirms (ask-first for ALL pins in V1), executes via CLI (`plugin uninstall --scope`, `plugin update -s`), then surfaces the resulting committed `.claude/settings.json` diff for review. Never runs implicitly from sync; sync only reports and names the converge command.
7. **Report**: terse fixed sections — marketplace state, updated, installed, divergences (live-vs-inactive named per repo), action needed. Detail only where action is required.
8. **autoUpdate posture**: report the marketplace's autoUpdate status and suggest enabling (complementary: background update-installed-to-latest once per session start, random ≤10-min delay). Never mutates the setting. The skill exists for what autoUpdate verifiably does not do: install new catalog plugins, enabledPlugins completeness, divergence detection/convergence, deterministic on-demand execution.

### Constraints

- **All mutations via the `claude plugin` / `claude plugin marketplace` CLI.** `installed_plugins.json`, `known_marketplaces.json`, `.last_inuse_sweep`, and cache version dirs are internal state: read-only, never written or deleted. No cache surgery — CC garbage-collects orphaned version dirs 7 days after update/uninstall.
- **Renames are CC-native** (≥ v2.1.193: settings rewritten old→new at session start; `null` = removal). The skill's only rename residue: anything in catalog but not installed gets installed (covers renamed plugins / `plugin-cache-miss`).
- **Never silently edit a repo's committed `.claude/settings.json`** — team-shared, trust-gated. Converge surfaces diffs; v2.1.203+ local-override path available for personal-only intent.
- **Never trust `plugin list`/`details` version output for what is LOADED** (verified misleading: shows highest installed, not the cwd-effective install). Effective-version claims derive from scope-by-cwd resolution (local > project > user, verified) or a functional probe.
- Non-interactive contexts: any `uninstall`/`prune` needs `-y`; autonomous sessions (`CLAUDE_CODE_REMOTE`, `/loop`, `/schedule`) must abort converge (repo destructive-tier convention).
- Repo conventions (migration playbook / philosophy): repo- and machine-agnostic (no hardcoded paths, names, or marketplace ids; `${CLAUDE_PLUGIN_ROOT}` / `${CLAUDE_PLUGIN_DATA}`); bash runtime (Git Bash on Windows) with OS detection; shared helpers only via `lib/hook-utils.sh` sync; `context/` progressive disclosure; `evals/evals.json` (~5–6 cases: routing, happy path, ≥1 refusal/guardrail, ≥1 anti-pattern) per skill-quality schema.
- Minimum CC version note in docs: renames map ≥2.1.193; `prune` ≥2.1.121.

### Acceptance criteria

- From a clean machine with the marketplace added: one `sync` run leaves every catalog plugin installed at user scope at latest version, enabledPlugins complete, and prints the terse report — idempotent (second run reports all-current, changes nothing).
- With a stale/corrupt marketplace clone: `sync` recovers via `marketplace update` (no manual re-clone) and proceeds.
- After an upstream rename wave: post-migration `sync` installs all new-named plugins; no old-name entries remain in user-scope state; nothing hand-edits internal JSON.
- Run inside a repo with divergent project-scope installs: report names, per plugin, which version is LIVE there vs inactive; sync updates the project-scope installs in place (subject to the deferred verification below); committed settings untouched.
- `audit` mutates nothing — issues zero mutating CLI calls; internal state files unchanged absent external writers (concurrent sessions / autoUpdate background sweep) — while predicting sync/converge actions accurately. *(Refined 2026-07-17 during plan stress-test: byte-identical-unconditionally is unprovable under CC's own background autoUpdate.)*
- `converge` on a drift repo: previews, confirms, consolidates to user scope via CLI, and the repo's settings diff (if any) is surfaced, not committed.
- New catalog plugin with `install_new: ask`: offered, not auto-installed; with `all`: installed; with `none`: reported only.
- Skill ships evals passing skill-quality schema validation; claude-ops version bumped with CHANGELOG + README entries.

### Captured assumptions

- Consumers run CC ≥2.1.193 (renames-map support); older CC degrades to `plugin-not-found` for renamed plugins — report guides upgrade.
- The marketplace's own `renames` map remains the single source of rename truth; skill hard-codes no rename knowledge.
- `install_new` policy applies per marketplace uniformly (no per-plugin allowlist in V1).

### Out-of-scope (deliberate)

- Cache-dir cleanup/GC (CC's 7-day orphan sweep owns it; manual deletion unsanctioned).
- Auto-uninstalling catalog-removed plugins (CC-native `renames: null` handles removal; skill reports only).
- Mutating marketplace `autoUpdate` or any CC setting.
- Managed-scope handling (enterprise) beyond reporting.
- Cross-machine fleet orchestration (per-machine command only).
- Per-plugin desired-set manifest (revisit if `install_new` policy proves too coarse).

### Deferred questions

- **Does `plugin update -s project` avoid writing the repo's committed `.claude/settings.json`?** Derived-likely (enabledPlugins carries no version; installs are machine-local records) but unverified. Arbiter: empirical test during implementation (run against a throwaway project scope; `git status` the repo settings) BEFORE the in-repo update path ships. USER-RESERVED if the answer is "it writes": the in-repo sync semantics (Decision 4) would need re-approval.
- **Is `/reload-plugins --force` required after sync, or is plain `/reload-plugins` sufficient?** Arbiter: /architect (verify against current CC docs/behavior at implementation; report guidance follows the answer).
- **`all`-marketplaces argument interaction with third-party marketplaces lacking renames maps / non-git sources** — RESOLVED by /architect: graceful degradation — `marketplace update` handles every source type; a marketplace without a `renames` map simply has no rename residue; failures per-marketplace are reported and do not abort the sweep.

## Plan

### Phase 1: Verify runtime facts (throwaway spike) [TODO]

Three unknowns gate later phases; resolve empirically on this machine before authoring semantics.

1. **`plugin update -s project` committed-file test** (USER-RESERVED gate — **go/no-go for the skill's primary value**: the in-repo update path is the main event, since dual-scope repos load the stale project pin): from `D:\repos\github.com\melodic-software\medley` — note its `.claude/settings.json` is ALREADY dirty, so porcelain status alone cannot detect the write. Method: SHA256 both `.claude/settings.json` and `.claude/settings.local.json` AND copy both to a backup dir; run `claude plugin update markdown-formatter@melodic-software -s project` (also fixes one real drift item: 0.1.3 → latest); re-hash and diff. If either file changed: restore from backup, record diff verbatim, **STOP — Brief Decision 4 needs user re-approval**.
2. **`/reload-plugins` `--force` necessity**: check current CC docs/help for `/reload-plugins` flags; empirically compare `/reload-plugins` vs `--force` after a plugin update. Record which the report should recommend.
3. **userConfig enum support**: fetch `json.schemastore.org/claude-code-plugin-manifest.json`; check whether `userConfig` entries support `enum`. Fallback: string field + prose validation in SKILL.md.
4. **Internal-schema parse contract snapshot**: copy the live shapes of `installed_plugins.json` (per-id array of `{scope, projectPath?, installPath, version, ...}`) and `known_marketplaces.json` into Phase 2 test fixtures, with a CC version-floor note (schema observed on 2.1.211; undocumented internal contract — parser must fail loud on shape drift, never guess).

**Sanity Check:** PLAN.md "Open questions" contains four lines matching `^- VERIFIED:` (one per unknown), each with observed evidence; item 1's line records both file hashes before/after verbatim; fixture files exist under `plugins/claude-ops/skills/plugins/scripts/fixtures/`.

### Phase 2: State-inspection script (TDD) [TODO]

| File | Action | What changes |
|------|--------|-------------|
| `plugins/claude-ops/skills/plugins/scripts/fleet-state.sh` | Create | Read-only state JSON per design-resolution type sketch; `--marketplace <name>` / `--all`; jq-based; fail-open notice on missing jq |
| `plugins/claude-ops/skills/plugins/scripts/fleet-state.test.sh` | Create | Fixture-driven tests written FIRST (Red-Green-Refactor) |

Fixtures: dual-scope divergence, plugin missing from installs, plugin missing from enabledPlugins, explicit `enabledPlugins: false` opt-out, marketplace absent, malformed/drifted JSON shape (must fail loud), native-Windows `projectPath` vs Git Bash cwd.

**Path normalization (CRITICAL, from plan review):** `installed_plugins.json` stores `projectPath` in native Windows form (`D:\repos\...`); Git Bash `$PWD` is `/d/repos/...`. In-repo detection MUST normalize both sides or it silently no-ops on Windows. Reuse `hook::normalize_path` from the plugin's synced `hook-utils.sh` copy (`plugins/claude-ops/hooks/hook-utils.sh` — already carried by this plugin; never hand-edit, sync via `scripts/sync-hook-utils.sh` if lib changes are needed).

**Sanity Check:** `bash fleet-state.test.sh` exit 0 including a Windows path-match assertion (`projectPath: D:\\...` fixture matched from cwd `/d/...`); repo bash-lint hook passes on both files; live run on this machine reports all 46 catalog plugins installed+enabled with zero `missing_*` entries.

### Phase 3: SKILL.md + context files [TODO]

| File | Action | What changes |
|------|--------|-------------|
| `plugins/claude-ops/skills/plugins/SKILL.md` | Create | Frontmatter (`user-invocable: true`, `disable-model-invocation: true`, argument-hint, description with "Use when"), Action Router table (sync default / audit / converge, `<marketplace>`/`all` args), terse-report section spec — bulk-divergence collapsed to one line ("N project-scope installs behind user scope → run converge"; per-row detail reserved for genuine conflicts: enable-state mismatch, unknown plugin, failures), `${CLAUDE_PLUGIN_ROOT}` script invocation |
| `plugins/claude-ops/skills/plugins/context/sync.md` | Create | Sync algorithm: marketplace update → in-repo project/local update when cwd is inside a project with installs (PRIMARY value path, per Phase 1 verdict) → user-scope update sweep → install-new per `install_new` policy → enabledPlugins completeness → report. "Missing" = in catalog AND never installed AND not explicitly `false` in any enabledPlugins scope; explicit `false` = deliberate opt-out, reported never flipped; `install_new: all` reinstall-on-every-sync behavior for uninstalled-but-not-disabled plugins documented as a caveat. Concurrency: CLI is the serialization point; re-read state immediately before each mutation (never mutate off a stale snapshot); autoUpdate background sweep may race — report notes it |
| `plugins/claude-ops/skills/plugins/context/converge.md` | Create | Divergence intent preview, per-plugin confirm, CLI execution, committed-diff surfacing; autonomous-session abort per the existing repo convention (`repo-hygiene` clean: `CLAUDE_CODE_REMOTE`, `/loop`, `/schedule` → abort destructive tier; fail-closed when context is uncertain) |
| `plugins/claude-ops/skills/plugins/context/scope-semantics.md` | Create | Verified facts: scope-by-cwd loading, enable-boolean override chain, `list`/`details` version display caveat, committed-vs-machine-local state map, renames-map CC-native behavior (floor ≥2.1.193; prune ≥2.1.121), autoUpdate complement, divergence-is-normal expectation |
| `plugins/claude-ops/skills/plugins/context/gotchas.md` | Create | list/details version lie, native-Windows projectPath, concurrency/TOCTOU, dual-scope-divergence-as-normal, internal-schema drift fail-loud |

**Sanity Check:** `grep -c '| `sync' SKILL.md` ≥ 1 and router table lists exactly sync/audit/converge; `grep -rn 'melodic-software' plugins/claude-ops/skills/plugins/` returns 0 normative occurrences (marketplace name always resolved dynamically); `grep -c 'CLAUDE_PLUGIN_ROOT' SKILL.md` ≥ 1; frontmatter contains `disable-model-invocation: true`.

### Phase 4: Evals [TODO]

| File | Action | What changes |
|------|--------|-------------|
| `plugins/claude-ops/skills/plugins/evals/evals.json` | Create | 6 cases: routing (bare invocation → sync), audit-is-read-only guardrail, install_new=ask prompting, converge-requires-confirm refusal (autonomous context), divergence report names live-vs-inactive, anti-pattern (never edits installed_plugins.json / cache dirs) |

**Sanity Check:** `bash plugins/skill-quality/scripts/check-skill.sh plugins/claude-ops/skills/plugins` reports zero WARN across ALL checks (gotchas surface satisfies Check 11); `jq '.evals | length' evals.json` ≥ 5.

### Phase 5: Plugin metadata [TODO]

| File | Action | What changes |
|------|--------|-------------|
| `plugins/claude-ops/.claude-plugin/plugin.json` | Modify | version 0.8.0 → 0.9.0; description includes new skill; `userConfig.install_new` per Phase 1 verdict |
| `plugins/claude-ops/CHANGELOG.md` | Modify | `## [0.9.0]` `### Added` entry |
| `plugins/claude-ops/README.md` | Modify | Skills section row + configuration note |

**Sanity Check:** `node scripts/validate-plugin-contracts.mjs` (or `bash scripts/validate-plugins.sh`) exit 0; `jq -r .version plugins/claude-ops/.claude-plugin/plugin.json` = `0.9.0`; `grep -c '\[0.9.0\]' CHANGELOG.md` = 1.

### Phase 6: End-to-end verification [TODO]

1. Install the branch build locally (or `/reload-plugins` against the dev copy per repo dev-loop convention), run `/claude-ops:plugins audit`: verify it issues ZERO mutating CLI calls (transcript inspection) and, absent concurrent sessions/autoUpdate sweeps, both internal JSON files hash identical before/after; report contains all five sections.
2. Run `sync` on this machine (steady state expected: all current) — idempotence: second run reports no changes.
3. Run `audit` from inside medley — divergence section present, bulk case collapsed to the one-line summary with live-vs-inactive versions named for at least the conflict rows.

**Sanity Check:** audit transcript contains no `plugin install|update|uninstall|marketplace update` invocations; before/after SHA256 of both internal JSON files identical (run with no other CC session live); sync run 2 output contains zero update/install lines; medley audit output contains the collapsed divergence summary line.

## Blast radius

LOW — additive skill in one plugin; no existing skill/hook/lib modified (plugin.json/CHANGELOG/README additive edits). Runtime mutations are user-invoked, CLI-mediated, reversible; the one committed-settings hazard is fenced behind `converge` confirm + Phase 1 USER-RESERVED gate.

## Stress-test summary

Plan-reviewer sub-agent (fresh context): 1 CRITICAL + 6 IMPORTANT + 3 SUGGESTION. All applied except: #4 partially (medley test kept — it exercises a real stale pin a fresh throwaway cannot manufacture; method hardened to hash-compare + backup/restore) and #6 downgraded (reviewer missed the existing `CLAUDE_CODE_REMOTE` autonomous-abort convention at `repo-hygiene/skills/clean/context/action-router.md:58` — converge aligns with it, fail-closed, no new research phase). CRITICAL #1 (native-Windows `projectPath` vs Git Bash cwd — in-repo detection would silently no-op) fixed in Phase 2 via `hook::normalize_path` reuse + test assertion. /devils-advocate: skipped — blast radius LOW, no triggers matched.

## Execution shape

Fully sequential: 1 → 2 → 3 → 4 → 5 → 6 — Phase 1 verdicts gate Phase 3 semantics; Phase 3 cites Phase 2's script interface; 4/5 document 3; 6 verifies all. Parallelism opportunity immaterial (<100 LOC independent).

| Phase | Surface | Basis |
|---|---|---|
| 1 | main-session | mutating empirical test + USER-RESERVED stop gate needs the user present |
| 2 | main-session | small TDD unit; dispatch overhead exceeds saving |
| 3–5 | main-session | judgment-heavy authoring against conventions |
| 6 | main-session | drives live machine state + user-visible reload |

## Open questions

- Phase 1 unknowns (three) — resolved lines land here as `- VERIFIED: ...`.

## Handoff to implementation

### User-approval gates

- Phase 1 item 1: if `plugin update -s project` writes the committed `.claude/settings.json` → STOP, re-approve Brief Decision 4.
- Any scope expansion beyond the Files Affected tables.

### Execution shape ([EXEC-SHAPE] tagged)

- [EXEC-SHAPE] Hybrid script/prose split: one read-only `fleet-state.sh` (repeatable-inspection convention) + model-driven CLI mutations (judgment + confirms involved).
- [EXEC-SHAPE] `disable-model-invocation: true` for the whole skill V1 (setup-skill precedent; mutating fleet ops are user-intent).
- [EXEC-SHAPE] `all`-marketplaces degradation: per-marketplace failures reported, sweep continues.
- [FALLBACK — confirm or override] userConfig `install_new` as enum; falls back to string + prose validation if the manifest schema lacks enum support (Phase 1 item 3 decides).

### Mechanical work

- Branch: create `feat/claude-ops-plugins-skill` from latest `origin/main` (current checkout sits on an unrelated feature branch — use a worktree per repo convention if that branch stays active).
- Commit boundaries: one commit per phase; PLAN.md tag updates ride the same commit.
- Sequential fallback: n/a (no parallel shape).

