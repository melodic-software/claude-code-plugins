# babysit-prs migration

## Brief

### TLDR

Converge two mature babysit implementations — the personal dotfiles skill (`~/.agents/skills/babysit-prs`, worker/autopilot auto-merge tiers, Python guard scripts, lease/worktree orchestration) and the `source-control:pull-request` skill's babysit mode (never-merge fleet loop) — into one new standalone `source-control:babysit-prs` skill, fully repo/machine/user-agnostic per plugin philosophy. Closes #260. The dotfiles skill, its Claude adapter, personal rails doc, and the entire Codex surface are then removed from dotfiles (clean delete, no backports).

### Goal

One skill, `/source-control:babysit-prs`, that:

- runs the fleet loop (discover, per-PR evaluate, fix, report) safe-by-default: own PRs, current
  repo's owner, never resolves threads, never merges;
- unlocks `worker` (auto-resolve outdated bot threads, merge behind the deterministic gate) and
  `autopilot` (all authors under watched owners, address-then-resolve any thread, merge-gated) as
  explicit opt-in tiers;
- ships the Python engine (decomposed from `pr_queue_snapshot.py`) with its relocated test suite;
- shares per-PR review discipline with `pull-request` via a plugin-scope seam;
- is configured via `userConfig` + extended `source-control:setup` (check/apply), with zero baked
  identities, paths, or org assumptions.

### Constraints

- **Migration input** = chezmoi source tree (`dot_agents/skills/babysit-prs`, last commit
  2026-07-16) **plus** every deployed-only delta analyzed and ported (notably per-repo `--repo`
  queue scoping, ported WITH its state-clobber bug fixed and lease/snapshot `--repo` pairing
  validated). Chezmoi source itself stays untouched; no dotfiles round-trip for improvements.
- **Composition (B13):** layered plugin-scope shared seam. Shared review discipline (finding
  extraction, D1–D7 verification gates, self-reply filter) + `fetch-all-pr-comments.sh` hoisted to
  plugin root, cited by both skills via `${CLAUDE_PLUGIN_ROOT}` paths (one committed copy,
  delivery-by-version). Babysit owns fleet mechanics (leases, cadence, discovery, fan-out,
  sharding); `pull-request` keeps single-PR lifecycle (prep/create/monitor/merge). Workers cite the
  shared seam directly — never load the `pull-request` router. `monitor.md`'s three
  cross-references into babysit invert cleanly.
- **Engine (B15):** Python snapshot engine is the backbone, decomposed (state store, gh API,
  feedback classification, review gate, delta engine, thin CLIs); `discover-prs.sh` retired;
  `babysit-readiness-gate.sh` kept at the shared seam. Python is a declared prerequisite for
  `worker`/`autopilot` only; the safe default path runs Python-free and degrades gracefully per the
  philosophy's failure-behavior rules.
- **Merge tier (B4):** safe default preserves the never-merge invariant; merge exists only behind
  explicit tier opt-in + the deterministic gate (`mergeStateStatus == CLEAN` cross-checks; never
  `--admin`, never force-push). Accept the plugin-acceptance security-review re-trigger for this
  new trust surface.
- **Review-bot module (B11):** the Codex-review vertical generalizes to a bot-agnostic AI-review
  trigger + gate module — config supplies trigger phrase, reviewer logins, gate context names; must
  handle inline review threads, posted summary comments (Claude-Code-review style), and check-run
  gates. Bot identity detection stays structural (`__typename == "Bot"` / `[bot]` suffix); zero
  hardcoded identities. No adapter layer until a real misfit appears.
- **Concurrency (B14):** layered detection over locking. L1 head-SHA recheck + push rejection;
  L2 design rule — every one-shot action derives dedup evidence from GitHub, local state is cache
  only; L3 foreign-activity detector (mutation-ledger vs same-login timeline diff → back off,
  report contention). File leases coordinate same-machine sessions under `${CLAUDE_PLUGIN_DATA}`;
  `--repo` sharding is the multi-tab contract.
- **Config (B5/B6):** zero user/machine/repo-specific content in the skill. Personal scalars →
  `userConfig` (watched owners, self logins, default tier, merge method, cadence bounds, fix-round
  cap, review-trigger settings, worktree root defaulting to `${CLAUDE_PLUGIN_DATA}/worktrees`);
  delivery to scripts via prose substitution → CLI flags (option env vars do not reach
  skill-invoked Bash); custom `BABYSIT_*` env seams retire per doctrine. Setup = extend
  `source-control:setup` (check + apply, idempotent). Dependabot/dependency PRs: hold-merge is the
  generic safe default in every tier.
- **Packaging:** guarded-helper wrappers move to plugin `bin/` with collision-safe plugin-prefixed
  names (auto-mode-surviving bare-name allow rules). Scripts ship `--help` + sibling
  cross-platform `.test.sh`; the 6,744-line Python test suite relocates into this repo's
  plugin-tests lane; wire Python lint/type coverage (ruff/pyright) or record the gap explicitly.
  UTF-8 handled inside scripts; invocation examples shell-neutral. Trigger-continuity migration
  table + routing evals required (skill split creates new paths `/skill-quality:check` skips).
- **Improvement backlog rides the migration** (no separate pre-pass): merge-gate `(type, name)`
  check dedup keying; bot-login fallback list → config; duplicate GraphQL paginators and subprocess
  runners collapsed; cadence cross-cycle counters persisted in the state file; SKILL.md/reference
  prose drift resolved. `references/plugin-migration.md` dies, superseded by this contract.
- **Process:** PR-A (extraction + shared seam, closes #260) → PR-B (capability convergence — the
  security-review PR) → cutover → dotfiles removal PR. Conventional-Commit titles, per-plugin
  CHANGELOG (Keep a Changelog, 0.x breaking-by-minor), `claude plugin validate --strict` from a
  non-source repo, PII gate before first commit. PR #256 naming grammar is binding but its merge is
  not a blocker; coordinate rebases with #271 (`prep.md` touch).

### Acceptance criteria

1. `/source-control:babysit-prs` exists; `pull-request` no longer mentions babysit (description,
   action table, checklists, README, eval 9, monitor cross-references all updated atomically).
2. Bare invocation with zero config in a fresh consumer repo: discovers own PRs under the current
   repo's owner, fixes clear branch-owned issues, reports, never resolves/merges. No Python needed.
3. `worker`/`autopilot` tiers function end-to-end on this fleet (leases, fan-out, gate-checked
   merge, thread resolution) with config supplied via userConfig/setup — no hardcoded owners,
   logins, contexts, or paths anywhere in the plugin (CI `machine-specific-paths` + gitleaks green).
4. Ported `--repo` sharding: two concurrent same-machine sessions scoped to different repos share
   no lease contention and do not clobber each other's snapshot state.
5. Relocated test suite green in the plugin-tests lane; every script has `--help` + `.test.sh`;
   `claude plugin validate --strict` passes; trigger-continuity table + evals present.
6. Cutover complete: active loop killed, plugin babysits this fleet in production, dotfiles
   kill-list removed (B9 list), `chezmoi status` clean, loop restarted on the plugin skill.
7. Freshness/re-anchor skill (B16): issue filed with boundary definition
   (vs `source-control:worktree` status and babysit rescan), then implemented — sequenced last.

### Captured assumptions

- GitHub-side AI reviewers (Codex/Claude/Cursor bots) remain in use org-side; only the local Codex
  runtime surface dies. The generalized review-trigger module keeps the Codex flow working via
  config.
- One machine owns a given repo's babysit at a time (human convention, L3-detected, not enforced).
- `find-skill-candidates` remains in `~/.agents` — out of scope here.

### Out-of-scope

- Cross-machine lease/claim infrastructure (L4 claim markers) — deferred; trigger: L1–L3 detection
  proves insufficient in real multi-machine operation.
- Review-bot interface/adapter layer — deferred; trigger: a feedback form config cannot express.
- Any Codex backport, parity shim, or dangling compatibility path — deliberately excluded.
- Changes to `standards` / `ci-workflows` / `github-iac` repos.

### Deferred questions

- Exact userConfig key names/types, module boundaries of the engine decomposition, evals content,
  lint-coverage wiring, L3 detector mechanics — arbiter: /architect (per phase PR).
- Freshness skill name, plugin placement (re-anchor vs elsewhere), and scan boundaries — arbiter:
  USER-RESERVED (shapes B16 scope; settle in its issue).
- Merge-method default resolution order (repo convention → squash) — arbiter: /architect.

## Plan

### Phase 1: PR-A — extraction + shared seam (closes #260) [DONE]

Extract babysit from `pull-request` into a sibling `babysit-prs` skill with behavior identical to
today's babysit mode (safe default only — tiers, engine, and config arrive in Phase 2), and hoist
the shared review discipline to plugin scope so neither skill loads the other's router.

**Step 0 — Gate 0 fresh-docs.** WebFetch the current official skills + plugins-reference pages
(URL table in root CLAUDE.md) before any manifest/structure change; cite both in the PR body.

**Step 1 — Hoist the shared seam to plugin scope.**

- Create `plugins/source-control/reference/review-discipline.md` — canonical home of the shared
  per-PR review discipline, extracted from `reference/babysit.md`: evidence-based fresh rescan +
  self-reply filter (§5.0.3), structured finding extraction + mandatory ≥3-finding subagent
  dispatch with the verbatim scope-fenced prompt + main-session contract (§5.0.4), and per-finding
  D1–D7 with GitHub-verification gates (§5.1.3 D-steps). Content moves verbatim-with-renumbering;
  babysit-specific framing (round-robin, wake scheduling) stays out.
- `git mv` to `plugins/source-control/scripts/`: `fetch-all-pr-comments.sh` + `.test.sh`,
  `babysit-readiness-gate.sh` + `.test.sh`, `test-helpers.sh` (single shared copy; sourced by
  tests on both sides). Update the two remaining pull-request test scripts that source it
  (`fetch-annotations.test.sh`, `fetch-failed-logs.test.sh`) to source
  `../../../scripts/test-helpers.sh` (and their `# shellcheck source=` directives);
  `parse-branch-issue.test.sh` never sourced the helper.
- Re-root every `${CLAUDE_PLUGIN_ROOT}/skills/pull-request/scripts/fetch-all-pr-comments.sh` and
  `.../babysit-readiness-gate.sh` citation to `${CLAUDE_PLUGIN_ROOT}/scripts/...`.
- Update `babysit-readiness-gate.sh`'s four internal doc-comment citations of `babysit.md §5.0.4`
  (lines 8, 21, 164, 216) to cite `review-discipline.md` with the post-renumbering section id.
- Layering end-state (one committed copy per B13): `review-discipline.md` is the canonical
  DETAILED home (extraction rules + subagent prompt + table formats + per-finding verification
  gates + self-reply filter); pull-request SKILL.md and the new babysit-prs SKILL.md each keep
  only the compact always-loaded checkbox skeleton citing the seam for detail; monitor.md keeps
  its monitor-specific batch-flow framing (§3.3) and cites the seam for the shared rules. No
  third detailed copy anywhere.

**Step 2 — Create the `babysit-prs` skill.**

- `git mv skills/pull-request/reference/babysit.md skills/babysit-prs/reference/loop.md`, then
  rework: hoisted sections (§5.0.3/§5.0.4/§5.1.3 discipline core) collapse to citations of the
  plugin-scope seam; self-pacing prompt strings become `/source-control:babysit-prs`; §5.0.2 keeps
  the inline `gh pr list` filter (deterministic-equivalent script retired); §5.1.1 carries its own
  compact event-delivery gate (cloud check → push channel → Monitor tool), with deep push-channel
  health detail cited from `pull-request`'s monitor reference (same-plugin file link, not the
  router).
- Retarget every cross-file prose reference in the moved content (grep-enumerated:
  `:169` "Monitor entry checklist from SKILL.md" → the skill's own SKILL.md checklist; `:318`
  "canonical policy: SKILL.md D7.5" → the seam file; `:337` `readiness.md` "Expected PR actors" and
  `:342` "monitor §3.2" / monitor.md "Inline vs subagent dispatch decision" and `:346`
  "differs from monitor.md step 4" → full same-plugin
  `${CLAUDE_PLUGIN_ROOT}/skills/pull-request/reference/...` citations or seam citations — never
  the pull-request router). Re-grep after rework: no bare `SKILL.md`/`monitor.md`/`readiness.md`
  reference in babysit-prs resolves to a pull-request surface implicitly.
- New `skills/babysit-prs/SKILL.md`: frontmatter (`name: babysit-prs`, user-invocable,
  description = imperative + quoted `Use when:` triggers carrying the migrated phrases
  ('babysit PRs', 'babysit my PRs', 'watch my open PRs', 'keep my PRs moving', /loop pairing) +
  negative routing ("not for single-PR prep/create/monitor/merge — use /pull-request")); purpose +
  never-merges invariant; the per-PR checklist (adapted from pull-request SKILL.md's babysit
  block); the NEVER list; checklist-driven output contract; pre-computed context block.
- **Phase-1 behavior honesty:** the description and purpose MUST describe today's discovery scope
  — every open non-draft PR in the current repo regardless of author (Dependabot included). The
  Brief's own-PRs-under-current-owner safe default is a Phase 2 deliverable (named in the Phase 2
  stub); Phase 1 ships behavior identical to the existing babysit action.
- New `skills/babysit-prs/evals/evals.json` (schema-valid, rich form): routing eval ('babysit
  my PRs' → this skill, not pull-request), negative-routing eval ('create pr' → pull-request),
  happy-path iteration eval, refusal eval (asked to merge a ready PR → declares readiness,
  refuses merge), anti-pattern eval (survey-without-classifying → violation; gate blocks
  readiness), plus ported eval 9 (merge-workflow preservation) with the new invocation.

**Step 3 — Remove babysit residue from `pull-request` atomically.**

- `SKILL.md`: description drops 'babysit PRs' and gains the negative route to the sibling; action
  table loses the `babysit` row; phases table loses `3+. Babysit`; the "Babysit per-PR checklist"
  block is deleted; monitor-entry Step 0 and per-iteration C4/D notes re-point their babysit.md
  citations to the plugin-scope seam or the sibling skill; script citations re-rooted.
- `reference/monitor.md`: the three cross-references into babysit.md (§5.0.4 extraction rules,
  §5.1.3 verification gates, §5.0.3 self-reply filter) invert to
  `plugins/source-control/reference/review-discipline.md`; script paths re-rooted.
- `evals/evals.json`: eval id 9 removed (ids stay stable; gap is legal per schema).
- Delete `scripts/discover-prs.sh` + `.test.sh` (retired per B15; inline `gh` filter is the
  contract).
- Sweep: `grep -ri babysit plugins/source-control/skills/pull-request/` returns only the
  deliberate sibling pointers (negative route, action-table pointer, monitor-entry note).

**Step 4 — Plugin metadata + catalog.**

- `plugin.json`: version `0.5.1` → `0.6.0` (0.x breaking-by-minor — the `babysit` action leaves
  the pull-request surface); description names both skills.
- `CHANGELOG.md`: `0.6.0` — Added (babysit-prs skill, plugin-scope review-discipline seam),
  Changed (pull-request babysit removal + re-rooted shared scripts, breaking), Removed
  (discover-prs.sh).
- `plugins/source-control/README.md`: babysit bullet becomes a `/source-control:babysit-prs`
  skill section (loop invocation updated to `/loop /source-control:babysit-prs`);
  `BABYSIT_SELF_LOGINS` row stays (unchanged behavior until Phase 2's userConfig).
- `.claude-plugin/marketplace.json`: source-control tags gain `babysit`; `plugin.json` `keywords`
  gains `babysit` in the same edit (same vocabulary axis).
- Root README regenerated via `node scripts/generate-catalog.mjs`.

**Step 5 — Validation + PR.**

- `bash scripts/run-plugin-tests.sh` (hoisted + remaining tests green), `bash
  scripts/validate-plugins.sh` (contracts, catalog `--check`, `claude plugin validate` per
  plugin and `--strict`), markdownlint, shellcheck, `claude --plugin-dir` smoke from a
  non-source repo (exercise `/source-control:babysit-prs` slash + automatic routing on 'babysit
  my PRs').
- `/skill-quality:check` on `pull-request` with `CHECK_SKILL_BASE_REF` set to the pre-change ref
  (playbook decompose step 5 — same-path rewrite): expect check 3 to flag the dropped
  `'babysit PRs'` trigger; the PR-body trigger-continuity table is the recorded answer.
- **Routing-smoke isolation:** the user-level dotfiles `/babysit-prs` skill is global and matches
  the same vocabulary — for the automatic-routing smoke, run a session with it disabled (or
  assert the plugin skill loads via explicit `/source-control:babysit-prs` and record the
  two-skills-one-vocabulary ambiguity as a known transition-window condition closed by Phase 3
  cutover).
- PR body: `Closes #260`, trigger-continuity migration table (each retired trigger phrase → the
  successor's quoted `Use when:` phrase + negative routing boundaries), Gate 0 citations, naming
  rationale for the verb-object leaf (`babysit-prs` carries its object for trigger continuity
  with the migrated vocabulary + disambiguation, verb-object compound precedent: scan-todos,
  youtube-digest), change set.
  Title: `refactor(source-control): extract babysit-prs skill from pull-request (0.6.0)`.
- Babysit the PR to merge with the current user-level `/babysit-prs` skill.

**Phase 1 file inventory:**

| File | Action |
|---|---|
| `plugins/source-control/reference/review-discipline.md` | CREATE (extracted content) |
| `plugins/source-control/scripts/fetch-all-pr-comments.sh` + `.test.sh` | MOVE (git mv) |
| `plugins/source-control/scripts/babysit-readiness-gate.sh` + `.test.sh` | MOVE (git mv) |
| `plugins/source-control/scripts/test-helpers.sh` | MOVE (git mv) |
| `plugins/source-control/skills/babysit-prs/reference/loop.md` | MOVE (git mv babysit.md) + rework |
| `plugins/source-control/skills/babysit-prs/SKILL.md` | CREATE |
| `plugins/source-control/skills/babysit-prs/evals/evals.json` | CREATE |
| `plugins/source-control/skills/pull-request/SKILL.md` | MODIFY |
| `plugins/source-control/skills/pull-request/reference/monitor.md` | MODIFY |
| `plugins/source-control/skills/pull-request/evals/evals.json` | MODIFY (drop id 9) |
| `plugins/source-control/skills/pull-request/scripts/{fetch-annotations,fetch-failed-logs}.test.sh` | MODIFY (helper path) |
| `plugins/source-control/skills/pull-request/scripts/discover-prs.sh` + `.test.sh` | DELETE |
| `plugins/source-control/.claude-plugin/plugin.json` | MODIFY (0.6.0) |
| `plugins/source-control/CHANGELOG.md` | MODIFY |
| `plugins/source-control/README.md` | MODIFY |
| `.claude-plugin/marketplace.json` | MODIFY (tags) |
| `README.md` | REGENERATE (catalog) |
| `plugins/source-control/skills/pull-request/reference/{prep,create,merge,readiness}.md`, `templates/checklist.md` | KEEP (grep-verified no babysit refs) |

**Sanity Check:**

- `grep -ri babysit plugins/source-control/skills/pull-request/` → only the deliberate sibling
  pointers (description negative route, action-table pointer, monitor-entry Step 0 note); zero
  babysit-owned content.
- `grep -rn "skills/pull-request/scripts/\(fetch-all-pr-comments\|babysit-readiness-gate\|discover-prs\|test-helpers\)" plugins/` → zero matches.
- `grep -rn "babysit\.md" plugins/source-control/` → zero matches (gate-script doc comments and
  all prose citations retargeted).
- `bash scripts/run-plugin-tests.sh` exit 0; `bash scripts/validate-plugins.sh` exit 0;
  `node scripts/generate-catalog.mjs --check` exit 0.
- `python -c "import json; d=json.load(open('plugins/source-control/skills/babysit-prs/evals/evals.json')); assert len(d['evals'])>=6"` exit 0.
- Non-source-repo smoke: `/source-control:babysit-prs` resolves and loads; 'babysit my PRs'
  routes to it.

### Phase 2: PR-B — capability convergence [TODO]

Port the dotfiles engine + tier system into `source-control:babysit-prs` (0.7.0), fully
generalized per B4/B5/B6/B11/B13/B14/B15. Migration input = chezmoi SOURCE tree + the deployed
`--repo` delta (with the state-clobber fix). Module boundaries, userConfig keys, and naming below
are the locked design (inventory: `design/phase-2-engine-modules.md`).

**Step 0 — Gate 0 fresh-docs.** Done at architect time (plugins-reference fetched 2026-07-17):
userConfig types `string|number|boolean|directory|file` + `multiple: true` string arrays;
`${CLAUDE_PLUGIN_DATA}` → `~/.claude/plugins/data/{id}/`, substituted anywhere in skill content,
env-exported to hooks only (NOT skill-invoked Bash — delivery is CLI flags from skill prose);
`bin/` PATH-joins per doctrine (plugin-prefixed collision-safe names). Cite in PR body.

**Lane E — engine decomposition (Python, file-disjoint from Lane D).**

New modules under `plugins/source-control/skills/babysit-prs/scripts/` (flat siblings, stdlib
only; `_babysit_common.py` absorbed and retired; per-symbol targets from
`map-snapshot-engine.md` §1):

- `babysit_util.py` — `configure_stdio` (UTF-8 inside scripts), JSON type helpers,
  `parse_timestamp`, `MIN_HEAD_SHA_PREFIX_LENGTH` (single copy — guard CLIs validate pins
  without importing state), and the SINGLE subprocess core `run_command` (argv allowlist param,
  timeout param default 60 via `--*-timeout-seconds` flags; raises on timeout; `check` param for
  never-raise callers). All three legacy runners collapse onto it. (Deliberately small mixed
  util module — recorded exception to the cohesion rule; splitting three ≤20-line concerns into
  three modules is worse.)
- `babysit_gh.py` — `run_gh`/`gh_json` over `run_command`; field lists; owner/repo regexes;
  `parse_repo_number` (absorbs `parse_ref`); ONE parameterized discovery function
  `discover_prs(owners=None, repos=None, author=None, limit, fields)` replacing
  `search_queue`/`reconcile_queue`/`discover_queue`/`discover_queue_for_repos` (axes: owner-search
  ∪ owner-repo-list vs explicit repos; zero-repo-owner tolerance; limit-reached detection;
  sorted output); `view_pr`; `fetch_blocked_base_compare`; REST pagination + fetchers;
  ONE GraphQL reviewThreads core `fetch_review_threads(repo, number, *, include_resolved,
  comments_first, projection)` (cursor loop + fail-closed pageInfo checks once; merge/resolve/
  snapshot projections become parameters); `find_open_prs_for_head_ref`.
- `babysit_state.py` — `--state-dir` flag primary, env `CLAUDE_PLUGIN_DATA` fallback, hard error
  when neither and on empty/filesystem-root paths (CODEX_HOME dies); lock/atomic-write;
  persisted projection + ledger merge; `save_state` WITH the scoped-run carve-out (a
  `--repo`-scoped complete run deletes only in-scope repo keys — fixes DEP:1985–2007 clobber)
  and `recommended_cadence` taken as a PARAMETER (no state→delta import);
  `resolve_expected_head_sha`; persisted cross-cycle counters `last_full_sweep_generated_at` +
  `cycles_since_full_sweep` (audit P3-16 — /loop fresh sessions stop forcing full sweeps).
- `babysit_lease.py` — lease library (map §2: four sibling CLIs import it): `lease_path`,
  acquire/heartbeat/release/reap cores, `require_owned_lease`, `load_lease`, `lease_expiry`,
  TTL defaults, `--steal-stale` logic — PLUS ported `--repo` lease scoping (deployed delta:
  repo-scoped queue leases keyed identically to snapshot `--repo` scope) and snapshot↔lease
  pairing validation (audit P3-19 — the lease record carries its scope; scoped snapshot runs
  validate against it). `manage_babysit_lease.py` becomes a thin shell over it.
- `babysit_checks.py` — check-state enums; category/normalize/summarize; dedupe + identity keyed
  by `(typename, name)` (fixes audit P2-5; the merge gate consumes the same keying); generic
  `classify_checks` (review-gate block extracted to the trigger module).
- `babysit_feedback.py` — actor typing (structural `__typename`/`[bot]` primary), bot-login
  fallback = config-supplied list + shipped-empty default (audit P2-6; `KNOWN_BOT_LOGINS`
  identity list dies); verdict regex battery; ONE review reduction (decisive filter = parameter,
  collapsing the `latest_reviews_by_author` twins); `review_commit_oid` (trigger module imports
  it from here); downgrade heuristics with reviewer logins from config; `collect_feedback`;
  human-stop derivation; dependency-manager author detection (Dependabot/Renovate-class bot
  taxonomy feeding the cross-tier hold-merge rule).
- `babysit_review_trigger.py` — B11 generalized module, config-driven (trigger phrase, reviewer
  logins, gate context, CI gateway context — ALL absent by default → module dormant,
  `gate_state == "absent"` degrade); the trigger phrase is defined HERE ONCE (posted comment and
  recognizer regex derive from the same value — kills the two-file duplication); request-state
  machine; evidence/reaction fetchers; the review-gate block of `classify_checks`.
- `babysit_delta.py` — `compute_branch_freshness`; fan-out gate constants +
  `max_quiet_recheck_seconds`; `classify_pr`; head-ref uniqueness guard; the 12 `needs_worker`
  delta arms PLUS the NEW L3 foreign-activity arm (B14: mutation-ledger entries diffed against
  the same-login GitHub timeline — foreign activity under our own login → suppress dispatch,
  surface a contention report); `recommend_cadence`; `head_repository_scope` mutation policy
  (consumers: classify, refresh CLI, review-trigger CLI); `ADVISORY_FIX_ROUND_CAP`
  (flag-overridable).

Thin CLIs (each `--help` + exit codes preserved): `pr_queue_snapshot.py` (adds `--repo` csv from
the deployed delta, validated owner∈watched set + against the queue lease's recorded scope;
`--owners`/`--author` defaults come from FLAGS the skill passes, not import-time capture — kills
DEP import-time `DEFAULT_OWNERS`), `babysit_merge.py` + `babysit_resolve_thread.py` (import
`babysit_util`/`babysit_gh`/`babysit_checks` plus exactly one pure function
`babysit_feedback.is_dependency_author` — never snapshot/delta/state; gate semantics preserved
incl. JSON `action`-field contract AND the owner-allowlist contract: both guard CLIs take
`--allowed-owners` csv replacing the retired `allowed_owners()`/`BABYSIT_OWNERS` channel and
FAIL CLOSED (refuse, exit 3) when the flag is absent — ported exit-3 tests rewire to the flag;
merge gate additionally keys check dedup by `(typename, name)`, REFUSES
dependency-manager-authored PRs absent an explicit `--allow-dependency` flag — hold-merge is the
cross-tier default — and REFUSES merge on unprotected repos (effective rules report zero
required reviews AND zero required contexts) when the author ∉ self logins, override
`--allow-unprotected`), `manage_babysit_lease.py` (thin shell over `babysit_lease`),
`manage_feedback_ledger.py`, `prune_babysit_worktrees.py` (dotfiles special-case DELETED;
`--root` default `${CLAUDE_PLUGIN_DATA}/worktrees` via flag; empty/rootish path hard error),
`refresh_pr_branch.py`, `request_review.py` (renamed from `request_codex_review.py`, fully
config-driven). Engine hardening from the formal stress-test: the ported reviewThreads paginator
pages/truncates-with-flag instead of RAISING on >100-comment and zero-comment threads;
persistently-erroring PRs quarantine (error classification + TTL) so one broken PR cannot pin
cadence at `active` forever; `queue-state.json` gains a `schema_version` stamp (writers stamp,
readers refuse/migrate on mismatch — Phase 3's migration validates against it); `load_state`
quarantines corrupt JSON to a timestamped `.corrupt` sibling and cold-starts loudly; the
`save_state` staleness guard and `recommended_cadence` become SCOPE-AWARE (compare only
in-scope records' `updated_at`) so two `--repo`-scoped sessions sharing the state file cannot
livelock discarding each other's saves; state-dir resolution is FLAG-ONLY (the env fallback
died — Gate 0 shows `CLAUDE_PLUGIN_DATA` never reaches skill-invoked Bash, and a stray shell
export must not silently redirect state).

Lane E also ports the engine test suite — all five files with named adaptation axes:
`tests/test_pr_queue_snapshot.py` (4,922 lines — module split, generalized `codex_*` →
`review_*` names, state-root change, flag-fed config), `tests/test_codex_review_race.py` →
`test_review_trigger_race.py` (config-driven trigger), `tests/test_babysit_merge.py` (457 —
`_babysit_common` retirement → new imports; dedup-keying + dependency-refusal cases),
`tests/test_babysit_resolve_thread.py` (840 — same import adaptation),
`tests/test_skill_contract.py` (133 — path retarget; runs at Lane C integration, NOT in Lane E's
local loop — SKILL.md lands in Lane D). New regression tests: scoped-run state preservation
(the clobber fix), two-scoped-sessions lease non-contention (AC4), `(typename, name)` check
dedup, discovery-function axis matrix, paginator projections + the no-raise
truncation behavior, L3 foreign-activity arm, dependency hold-merge refusal, unprotected-repo
refusal, guard-CLI allowlist fail-closed (exit 3 absent flag), scope-aware staleness guard under
interleaved save/ledger schedules, corrupt-state quarantine, schema_version stamp/refusal, and
guard-argv provenance (argv built only from validated refs/SHAs — untrusted PR text can never
reach it). Wrapper `engine.test.sh` (python/python3 detection, SKIP when
absent, `unittest discover` excluding the contract test until integration; runs `ruff check`
first when ruff is on PATH — self-SKIP otherwise; pyright NOT wired, gap recorded in PR body).

**Lane D — skill surfaces (docs/evals/config, file-disjoint from Lane E).**

- FIRST work item — substitution smoke: verify `multiple: true` array serialization through
  `${user_config.KEY}` in skill content empirically (`--plugin-dir` probe; record in
  `docs/extensibility-contract-smoke-tests.md`). Fallback if arrays don't substitute as usable
  csv: the multiple-valued keys become single comma-joined strings. This locks the delivery
  matrix BEFORE any invocation prose is written.
- `SKILL.md` rework: tier grammar `[worker|autopilot|help] [scope]`; mode table + scope ladder
  (safe default NARROWS per AC2: own PRs — author = self-login — under the current repo's owner,
  inferred when `watched_owners` unset); per-action-class tier matrix; cross-tier invariants
  (incl. dependency-PR hold-merge in EVERY tier); a substituted **effective-config block** — the
  always-loaded SKILL.md is the ONLY surface where `${user_config.*}`/`${CLAUDE_PLUGIN_DATA}`
  substitute; it renders every key + resolved value once, and reference-file command examples
  use placeholder-free `<angle-bracket>` slots the agent fills from that block (reference files
  are Read raw — no substitution happens there); honest default-tier wording — bare invocation
  runs the CONFIGURED default tier, `safe` unless the consumer changed it (contract-test
  literals preserved: the none-row still reads `Never resolves threads or merges.` as the safe
  tier's row); merge-capable tiers additionally require the EXPLICIT tier keyword in the
  invocation — `default_tier` acts only on explicit invocations (the documented /loop pairing),
  never on auto-routed 'babysit my PRs' matches, so config cannot convert a casual invocation
  into standing merge authority; per-tier draft policy (drafts enter evaluation scope in all
  tiers — safe reports, worker/autopilot route zero-blocker drafts through a worker,
  `gh pr ready` only in autopilot — replacing Phase 1's blanket `isDraft` skip).
- References (short-noun names per plugin precedent): `reference/loop.md` (existing; discovery
  filter gains the author/owner narrowing + tier-aware framing; the `isDraft == false` filter and
  "Skip isDraft" bullet replaced by the per-tier draft policy; §5.3 self-pacing REWORKED — when
  python is present the wake interval derives from the snapshot's `recommended_cadence`
  (active 5m / normal 15m / quiet 1h / idle daily), the static 60s/270s/1200s ladder demotes to
  the python-free degrade path — one cadence owner), NEW `reference/orchestration.md`
  (fan-out gate + arms, concurrency cap, leases incl. token rotation + re-acquire rules, worker
  contract + prompt template with `/source-control:babysit-prs` phrasing AND untrusted PR fields
  — titles, check names, `needs_worker_reasons` — fenced as quoted DATA in the template, never
  instructions; worker auto-resolve constrained to threads already outdated in the PRE-push
  snapshot via the thread pins, correcting the ported `isOutdated ⇒ addressed` claim; fallback,
  cleanup), NEW `reference/cadence.md` (states/thresholds/persisted counters; Codex-automation
  sections dropped), NEW `reference/freshness.md` (guarded refresh, BLOCKED compare fallback,
  202-async terminality), NEW `reference/review-trigger.md` (generalized trigger/gate semantics,
  dormant-when-unconfigured), NEW `reference/worktrees.md` (ephemeral policy + prune commands,
  `${CLAUDE_PLUGIN_DATA}/worktrees` root), NEW `reference/safety.md` (role boundaries, verify-
  before-escalate, harness permission layer incl. pinned-command degradation, stop-ask/never-do;
  repo-topology.md salvage kernel: worktree reuse, head-SHA recheck, mutation_policy,
  head-ref uniqueness, lease-protected removal). Every `$HOME\.agents`, CODEX_HOME, owner tuple,
  medley/dotfiles reference dies; script invocations cite
  `${CLAUDE_PLUGIN_ROOT}/skills/babysit-prs/scripts/` with explicit flags; shell-neutral examples.
- Feedback-classification prose: engine-behavior doc lives in `reference/feedback.md` (blocking/
  material rules, dispositions, advisory cap, bot-PR taxonomy, human-feedback policy) citing the
  plugin-scope `review-discipline.md` seam for the shared per-PR discipline — no second detailed
  copy (B13).
- `plugin.json` `userConfig` (all non-sensitive; delivery contract = SKILL.md effective-config
  block → explicit CLI flags per the key→flag matrix in `design/phase-2-engine-modules.md`):
  `watched_owners` (string, multiple; absent → infer current repo owner), `self_logins` (string,
  multiple; absent → `gh api user`; ALSO delivered to the seam gate via its existing `--self`
  flag), `default_tier` (string, default `safe`), `merge_method` (string; absent → repo
  convention → squash), `review_trigger_phrase` / `review_bot_logins` (multiple) /
  `review_gate_context` / `ci_gateway_context` (all absent → trigger module dormant; recorded
  single-org simplification — per-repo divergence is the trigger to move these to the tracked
  `.claude/source-control.md` seam), `extra_bot_logins` (string, multiple, structural detection
  primary), `max_quiet_recheck_seconds` (number, 14400), `advisory_fix_round_cap` (number, 100),
  `worker_concurrency_cap` (number, 10), `worktree_root` (directory; absent →
  `${CLAUDE_PLUGIN_DATA}/worktrees`). The PYTHON `BABYSIT_*` env seams retire (flags replace
  them); the seam gate's `--self`/`BABYSIT_SELF_LOGINS` bash contract is OUT of Phase 2 scope
  (plugin-root seam untouched — retirement claim scoped accordingly in CHANGELOG).
- `skills/setup` extension: babysit section — check mode probes effective config (reports each
  key's resolved value/inference), branch-protection posture across watched repos (unprotected
  repos flagged — the merge gate refuses them for non-self authors), and Windows long-path
  support for the worktree root; apply mode documents `/plugin` config dialog +
  `claude plugin install --config` (setup never hand-edits `pluginConfigs`).
- Evals: NEW routing (worker/autopilot keywords), tier-refusal (merge request in safe mode
  refused), gate eval (unpinned merge refused), dormant-trigger eval, dependency-hold eval,
  non-safe-default-tier honesty eval; REVISE Phase-1 cases that encode the old any-author
  Dependabot-included discovery to the narrowed AC2 default; README skill section + config table
  (`BABYSIT_SELF_LOGINS` row becomes the userConfig table; gate `--self` note stays).

**Lane C — guard wrappers + integration (after E+D land).**

- `plugins/source-control/bin/`: `source-control-babysit-merge` +
  `source-control-babysit-resolve-thread` — names PINNED NOW so Lane D docs cite the bare names
  (audit P3-18: guarded helpers are invoked by bare wrapper name, never interpreter-prefixed —
  auto-mode allow rules survive). Self-locating wrappers over the guard CLIs; interpreter
  resolution probes FUNCTIONALITY not PATH presence (`<candidate> -c "import sys"` — Windows
  Store aliases exist on PATH and fail at run time) over `py -3` → `python3` → `python`, with a
  clear absent-python degrade message and a declared Python version floor (README + wrapper;
  floor verified against the ported syntax at implementation); PYTHONUTF8 set inside; the merge
  wrapper REJECTS `--allow-unpinned-head` (the CLI keeps it for interactive/debug use, but the
  wrapper — the only allow-rule-covered invocation — cannot pass it, so no unattended unpinned
  merge exists); allow-rule migration is TWO-PHASE ADDITIVE (new
  `Bash(source-control-babysit-{merge,resolve-thread}:*)` rules land BEFORE cutover, inert until
  the plugin ships; the old `babysit_merge.sh` rule is removed in the Phase-3 dotfiles PR — no
  window where neither rule matches).
- `plugin.json` 0.7.0 + description; CHANGELOG 0.7.0 (Added: tiers/engine/userConfig/bin;
  Changed: safe-default discovery narrowed — breaking-by-minor; Removed: Python `BABYSIT_*` env
  seams — scoped claim, the bash seam gate's contract is untouched); marketplace keywords/tags
  unchanged (babysit already present); catalog regenerate.
- Validation: `run-plugin-tests.sh` (engine suite + skill-contract test now included + existing
  69 suites), `validate-plugins.sh`, markdownlint, shellcheck, `/skill-quality:check` with
  `CHECK_SKILL_BASE_REF` on BOTH same-path rewrites (`babysit-prs/SKILL.md`,
  `setup/SKILL.md`), non-source-repo smoke (`--plugin-dir`: safe bare invocation discovers own
  PRs zero-config; `worker` names Python prerequisite when absent).
- PR: title `feat(source-control): converge babysit-prs tiers + engine (0.7.0)`, body carries
  Gate 0 citations, security-review section (EIGHT surfaces: code-execution — untrusted PR/issue
  text never unquoted into shell, reviewed at the subprocess seam; no MCP; no secrets in
  userConfig; state contained under `${CLAUDE_PLUGIN_DATA}`; egress = git/gh only; provenance =
  chezmoi source SHA + deployed-delta list; bin/-PATH surface — first `bin/` in the fleet,
  collision-safe prefixed names, per-wrapper provenance recorded; prompt-injection-via-PR-content
  — untrusted fields fenced as data in snapshot output and the worker prompt, guard-CLI argv
  provably built from validated refs/SHAs only, plus the NAMED RESIDUAL RISK that gate scope
  flags are agent-supplied per-call — readiness stays gate-verified, scope relies on the
  wrapper's rejected-flag set + allow-rule surface; out-of-band policy file deferred with
  trigger), merge-tier trust-surface note re-triggering plugin-acceptance review, dotfiles→plugin trigger-continuity table (worker/
  autopilot/24-7 vocabulary → the new `Use when:` phrases — Phase 3 retires the dotfiles skill
  on this evidence), `Relates to #260` + literal `No linked issue` line per linkage gate.
  Babysit to merge with the user-level skill (still live until cutover).

**Phase 2 file inventory:**

| File | Action | Lane |
|---|---|---|
| `skills/babysit-prs/scripts/babysit_util.py` | CREATE | E |
| `skills/babysit-prs/scripts/babysit_gh.py` | CREATE | E |
| `skills/babysit-prs/scripts/babysit_state.py` | CREATE | E |
| `skills/babysit-prs/scripts/babysit_checks.py` | CREATE | E |
| `skills/babysit-prs/scripts/babysit_feedback.py` | CREATE | E |
| `skills/babysit-prs/scripts/babysit_review_trigger.py` | CREATE | E |
| `skills/babysit-prs/scripts/babysit_delta.py` | CREATE | E |
| `skills/babysit-prs/scripts/pr_queue_snapshot.py` | CREATE (thin CLI) | E |
| `skills/babysit-prs/scripts/babysit_merge.py` | CREATE (port) | E |
| `skills/babysit-prs/scripts/babysit_resolve_thread.py` | CREATE (port) | E |
| `skills/babysit-prs/scripts/babysit_lease.py` | CREATE (library + --repo scoping) | E |
| `skills/babysit-prs/scripts/manage_babysit_lease.py` | CREATE (thin shell) | E |
| `skills/babysit-prs/scripts/manage_feedback_ledger.py` | CREATE (port) | E |
| `skills/babysit-prs/scripts/prune_babysit_worktrees.py` | CREATE (port, de-specialized) | E |
| `skills/babysit-prs/scripts/refresh_pr_branch.py` | CREATE (port) | E |
| `skills/babysit-prs/scripts/request_review.py` | CREATE (generalized port) | E |
| `skills/babysit-prs/scripts/tests/test_*.py` (5 ported + new regressions; contract test wired at Lane C) | CREATE (adapted port) | E |
| `skills/babysit-prs/scripts/engine.test.sh` | CREATE | E |
| `docs/extensibility-contract-smoke-tests.md` | MODIFY (multi-value substitution record) | D |
| `skills/babysit-prs/SKILL.md` | MODIFY (tiers; contract-test constrained) | D |
| `skills/babysit-prs/reference/loop.md` | MODIFY (narrowed discovery) | D |
| `skills/babysit-prs/reference/{orchestration,cadence,freshness,review-trigger,worktrees,safety,feedback}.md` | CREATE | D |
| `skills/babysit-prs/evals/evals.json` | MODIFY (tier/gate evals) | D |
| `skills/setup/SKILL.md` | MODIFY (babysit config section; no reference dir exists — content stays in SKILL.md unless it outgrows it) | D |
| `plugins/source-control/.claude-plugin/plugin.json` | MODIFY (0.7.0 + userConfig) | D→C |
| `plugins/source-control/bin/source-control-babysit-{merge,resolve-thread}` | CREATE | C |
| `plugins/source-control/CHANGELOG.md` | MODIFY (0.7.0) | C |
| `plugins/source-control/README.md` | MODIFY (tier/config docs) | D |
| `README.md` | REGENERATE | C |
| `plugins/source-control/reference/review-discipline.md`, `scripts/*` (seam) | KEEP (grep-verified untouched) | — |
| `skills/pull-request/**` | KEEP (no PR-B edits) | — |

**Sanity Check (Lane E):**

- `bash plugins/source-control/skills/babysit-prs/scripts/engine.test.sh` exit 0 (suite green
  locally with python present).
- `grep -rn "CODEX_HOME\|BABYSIT_OWNERS\|BABYSIT_SELF_LOGINS\|BABYSIT_GH_TIMEOUT\|BABYSIT_COMMAND_TIMEOUT\|BABYSIT_MAX_QUIET" plugins/source-control/skills/babysit-prs/scripts/` → zero matches.
- `grep -rn "kyle-sexton\|melodic-software\|melodic-standards-sync\|chatgpt-codex-connector" plugins/source-control/skills/babysit-prs/scripts/` → zero matches (test fixtures use example.org-style names).
- `grep -c "def fetch_review_threads" scripts/babysit_gh.py` = 1 AND
  `grep -rn "reviewThreads" scripts/*.py | grep -v babysit_gh` → zero (single paginator).
- `grep -rn "subprocess.run" scripts/*.py | grep -v babysit_util` → zero (single runner).
- `python scripts/pr_queue_snapshot.py --help` exit 0; same for all 8 CLIs.
- Scoped-clobber regression test name greps present in `tests/test_pr_queue_snapshot.py`; lease
  two-scoped-sessions non-contention test present in the lease test module; L3 arm + dependency
  hold-merge test names grep-present.
- `grep -rn "test_skill_contract" scripts/engine.test.sh` shows the explicit
  until-integration exclusion.

**Sanity Check (Lane D):**

- `python plugins/source-control/skills/babysit-prs/scripts/tests/test_skill_contract.py` exit 0
  against the new SKILL.md (every §6 anchor + literal present) — run at Lane C integration once
  Lane E's port exists; Lane D's local check is the §6 table walked line-by-line against the
  drafted SKILL.md.
- `grep -rn "\.agents\|CODEX_HOME\|codex\|Codex" plugins/source-control/skills/babysit-prs/` →
  only the generalized review-trigger doc's neutral mentions if any; zero path/product couplings
  (case-insensitive sweep reviewed line-by-line).
- `python -c "import json; d=json.load(open('plugins/source-control/.claude-plugin/plugin.json')); assert set(d['userConfig'])>= {'watched_owners','self_logins','default_tier','merge_method','max_quiet_recheck_seconds'}"` exit 0.
- Eval count ≥ 10 and schema-valid via validate-plugins lane.

**Sanity Check (Lane C / integration):**

- `bash scripts/run-plugin-tests.sh` exit 0; `bash scripts/validate-plugins.sh` exit 0;
  markdownlint + shellcheck clean; `node scripts/generate-catalog.mjs --check` exit 0.
- Non-source-repo smoke transcript in PR body (zero-config safe run + worker-without-python
  degrade message).
- CI `machine-specific-paths` + gitleaks green on the PR.

### Phase 3: Cutover [TODO]

*(loop kill → plugin install/enable → userConfig set for this fleet → setup apply → ONE-SHOT
state migration: copy live `queue-state.json` into `${CLAUDE_PLUGIN_DATA}/state/babysit-prs/`
with `codex_*` schema keys renamed to their `review_*` successors via a documented single
python/jq command — preserves seen-feedback IDs, request/attempt histories, and dispositions so
the fleet does not cold-start into re-notification churn; cold start is the accepted fallback if
the copy fails validation → smoke one repo → dotfiles removal PR (kill-list B9; incl. the
`Bash(babysit_merge.sh:*)` allow rule renamed to the plugin wrapper names) → MANUAL chezmoi
apply → loop restart on `/source-control:babysit-prs worker`.)*

### Phase 4: B16 freshness/re-anchor skill [TODO]

*(issue first — name/placement USER-RESERVED; note the `re-anchor` plugin now exists (PR #293)
as a placement candidate; implement after user sign-off.)*

## Blast radius

Phase 1: MEDIUM — restructures the plugin's highest-traffic skill surface and its script paths;
consumers of `/pull-request babysit` (the user's live loop) lose the action at upgrade time, which
the cutover phase handles deliberately. No cross-plugin or cross-repo edits; CI gates
(plugin-tests, validate, catalog, markdownlint, shellcheck) cover every changed artifact class.

Phase 2: HIGH — ships an auto-merge trust surface (worker/autopilot tiers + deterministic gate),
the fleet's first `bin/` PATH executables, and a ~5k-LOC engine port consumed by a 24/7
production loop after cutover. Formal stress-test ran (summary below); plugin-acceptance
security review re-triggers on the PR by design.

## Stress-test summary

Fresh-context plan reviewer (Step 3) returned 6 IMPORTANT + 2 SUGGESTION findings, all verified
against the actual files and folded into Phase 1: gate-script internal `babysit.md` citations
(sweep pattern extended), unenumerated cross-file prose references in the moved content (explicit
retarget list added), the mandated `/skill-quality:check` `CHECK_SKILL_BASE_REF` run on the
same-path pull-request rewrite (added to Step 5), routing-smoke confound with the still-installed
user-level skill (isolation mechanism stated), Phase-1 discovery-scope honesty vs the Brief's
Phase-2 safe-default narrowing (pinned in Step 2 + Phase 2 stub), discipline-layering end-state
(one detailed copy at the seam, compact skeletons cite it), plus keywords/tags parity and the
naming-rationale PR-body note. Reviewer verified clean: test-runner discovery, no fixture/`../`
couplings in moved tests, no new drift-check cluster, catalog generation, exec-bit preservation,
eval-id gap legality, and the KEEP rows. Blast radius MEDIUM with all triggers covered by CI
gates + the Phase-3 cutover design — no `/devils-advocate` escalation warranted (the extraction
is structure-preserving; the new trust surface arrives in Phase 2, which gets its own pass).

**Phase 2 pass (2026-07-17):** fresh-context plan reviewer returned 1 CRITICAL + 16 IMPORTANT +
5 SUGGESTION — all 22 verified against disk/maps and folded (headliners: lease half of the
`--repo` contract was missing (AC4), `babysit_lease.py` module added, userConfig delivery matrix
pinned with a substitution smoke as Lane D's first item, SKILL.md effective-config block is the
only substituted surface, draft-policy and cadence-ownership contradictions with Phase-1
surfaces reconciled, env-retirement claim scoped to the Python seams, contract-test placement
ordering fixed). Formal `/devils-advocate` (blast radius HIGH — auto-merge tier, first fleet
`bin/`) returned PROCEED-WITH-FIXES: 1 CRITICAL (guard CLIs lost their owner-allowlist input
channel when `BABYSIT_OWNERS` retired — now `--allowed-owners`, fail-closed) + 5 HIGH (ambient
tier authority, unprotected-repo CLEAN merge, scoped-session save livelock, agent-supplied gate
scope, prompt-injection surface) + 6 MEDIUM + 4 LOW — all folded above; residual risk (gate
scope flags are agent-supplied) is NAMED in the PR's security-review section with the
out-of-band policy file deferred with trigger.

## Execution shape

Phase 1 is fully sequential in the main session — every step edits the same tightly-coupled skill
pair (SKILL.md ↔ reference ↔ scripts ↔ evals ↔ metadata), and total churn is well under the
parallelism-payoff threshold. Phase 2's execution shape is computed by its own architect pass.

| Phase | Surface | Basis |
|---|---|---|
| 1 (PR-A) | main session, sequential | coupled edits, judgment-heavy rewording |
| 2 (PR-B) | Wave 1: Lane E ∥ Lane D (subagent workers) → Wave 2: Lane C main session | E (scripts/tests) and D (SKILL/references/evals/manifest-userConfig/setup) share zero files; C needs both landed |
| 3 (cutover) | main session | live-loop + machine state, inherently serial |
| 4 (B16) | main session | issue-writing + user gate |

**Phase 2 scope fences.** Lane E ALLOWED: `plugins/source-control/skills/babysit-prs/scripts/**`
only. Lane D ALLOWED: `plugins/source-control/skills/babysit-prs/{SKILL.md,reference/**,
evals/**}`, `plugins/source-control/skills/setup/**`, `plugins/source-control/README.md`,
`plugins/source-control/.claude-plugin/plugin.json` (userConfig block only),
`docs/extensibility-contract-smoke-tests.md` (substitution-smoke record). BOTH FORBIDDEN:
PLAN.md, `skills/pull-request/**`, plugin-root `reference/`+`scripts/` seam, CHANGELOG (Lane C
owns), marketplace.json, root README. Sequential fallback: E → D → C in the main session if a
lane violates its fence or cannot complete. Cost: 2 concurrent workers vs sequential ≈ halves
wall-clock on ~4–5k LOC of ported work.

## Open questions

None for Phases 1–2 (module boundaries, userConfig keys, eval content, lint wiring, and L3
mechanics resolved at the Phase-2 architect pass — see `design/phase-2-engine-modules.md`).
B16 naming/placement is USER-RESERVED.

## Handoff to implementation

### User-approval gates

- The overall execution was pre-approved top-to-bottom by the user's handoff directive; Phase 1
  contains no further gates.
- Phase 3 retains the MANUAL `chezmoi apply` step (never from a loop session).
- Phase 4 blocks on user sign-off of the B16 issue (name/placement USER-RESERVED).

### Execution shape ([EXEC-SHAPE] tagged)

| Decision | What it changes in the plan | Basis |
|---|---|---|
| [EXEC-SHAPE] Retire `discover-prs.sh` in Phase 1, not Phase 2 | Step 3 deletes it; loop.md §5.0.2 keeps the inline `gh` filter | B15 already retired it; porting it into the new skill only to delete next PR is churn |
| [EXEC-SHAPE] Seam artifacts land at `plugins/source-control/reference/` + `plugins/source-control/scripts/` | Steps 1–2 paths | repo precedent: 9 plugins ship plugin-root `reference/`, 2 ship plugin-root `scripts/` with `.test.sh` (skill-quality); playbook step 4 mandates plugin-scope shared policy |
| [EXEC-SHAPE] `babysit.md` → `reference/loop.md` via `git mv` + rework | Step 2 history-preserving move | rename-PR precedent (history preserved); content survives mostly intact |
| [EXEC-SHAPE] `test-helpers.sh` hoists (single copy) | Step 1; three remaining tests re-point | no-duplication rule; hoisted tests need it; helper is skill-agnostic |
| [EXEC-SHAPE] eval id 9 removed without renumbering | Step 3 | schema declares ids stable identifiers; gaps legal |
| [EXEC-SHAPE] version 0.6.0 | Step 4 | 0.x breaking-by-minor: `babysit` action leaves the pull-request surface |
| [EXEC-SHAPE] marketplace tags gain `babysit` | Step 4 | discovery parity with the moved trigger vocabulary |
| [EXEC-SHAPE] Phase 2: 7 flat modules + thin CLIs (no package dir) | Lane E layout | per-symbol targets in map-snapshot-engine §1; flat siblings keep path-invoked CLIs importing without packaging machinery |
| [EXEC-SHAPE] Phase 2: guard CLIs import util/gh/checks only | merge/resolve auditability | preserves deliberate decoupling the source encoded, while collapsing duplicate paginator/runner per Brief backlog |
| [EXEC-SHAPE] Phase 2: review-trigger module dormant-by-default (no baked trigger/logins/contexts) | userConfig defaults | B5 zero baked identities; `gate_state == "absent"` degrade already in engine |
| [EXEC-SHAPE] Phase 2: merge-method resolution = repo convention → squash | merge gate default | Brief deferred question, arbiter architect; matches fleet practice and `/pull-request` merge doc |
| [EXEC-SHAPE] Phase 2: ruff opportunistic in engine.test.sh (self-SKIP), pyright gap recorded | lint wiring | repo has no Python lint lane; ci-workflows changes out of scope per Brief |
| [EXEC-SHAPE] Phase 2: lease steal/heartbeat windows stay CLI-flag defaults, not userConfig | config surface | operator-tunable per invocation, not identity/policy scalars — key-sprawl guard |
| [EXEC-SHAPE] Phase 2: version 0.7.0, `Relates to #260` + literal `No linked issue` | Lane C metadata | #260 closed by PR-A; linkage gate needs the literal line |
| [EXEC-SHAPE] Phase 2: guard CLIs take `--allowed-owners`, fail closed absent | replaces retired `BABYSIT_OWNERS` channel | stress-test CRITICAL: map §2 + live source show merge/resolve enforce owner scope via `allowed_owners()`; retiring the env without a flag deletes the gate's first contract line |
| [EXEC-SHAPE] Phase 2: merge-capable tiers require the explicit keyword; `default_tier` never acts on auto-routed invocations | SKILL.md mode semantics | stress-test HIGH: config must not convert casual auto-routed invocations into standing merge authority |
| [EXEC-SHAPE] Phase 2: merge gate refuses unprotected repos for non-self authors (`--allow-unprotected` override) | merge CLI rule + setup probe | stress-test HIGH: `CLEAN` is satisfiable with zero required checks/reviews on unprotected repos; autopilot widens authors |
| [EXEC-SHAPE] Phase 2: bin/ wrapper rejects `--allow-unpinned-head`; CLI keeps it for interactive use | wrapper contract | no unattended unpinned merge while preserving ported test surface + debug path |
| [EXEC-SHAPE] Phase 2: `schema_version` stamp, scope-aware staleness guard + cadence, corrupt-state quarantine, paginator no-raise, error-TTL quarantine, flag-only state dir | engine hardening set | stress-test findings #4, #8, #11, #13, #16 — each has a named regression test in Lane E |

### Mechanical work

- One commit per plan step is not required; commit at green checkpoints with Conventional-Commit
  subjects; PLAN.md phase-tag updates ride the same commits.
- Sequential fallback: not applicable in Phase 1 (already sequential).
- PII gate before first commit: moved content is already public in-repo; new content carries no
  identities beyond the generic `gh api user` default.
