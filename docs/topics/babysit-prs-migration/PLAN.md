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

### Phase 1: PR-A — extraction + shared seam (closes #260) [DOING]

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

*(architect per phase PR — engine decomposition module boundaries, tiers + merge gate,
review-trigger module, userConfig/setup, bin/ wrappers, L2/L3 concurrency, test-suite relocation.
Also: narrow the safe default's discovery scope from all-open-PRs (Phase 1 parity) to own PRs
under the current repo's owner per the Brief's Goal/AC2. Independent lanes orchestrated after
boundaries are fixed.)*

### Phase 3: Cutover [TODO]

*(loop kill → plugin install/enable → setup apply → smoke test → dotfiles removal PR (kill-list
B9) → MANUAL chezmoi apply → loop restart on `/source-control:babysit-prs worker`.)*

### Phase 4: B16 freshness/re-anchor skill [TODO]

*(issue first — name/placement USER-RESERVED; note the `re-anchor` plugin now exists (PR #293)
as a placement candidate; implement after user sign-off.)*

## Blast radius

MEDIUM — Phase 1 restructures the plugin's highest-traffic skill surface and its script paths;
consumers of `/pull-request babysit` (the user's live loop) lose the action at upgrade time, which
the cutover phase handles deliberately. No cross-plugin or cross-repo edits; CI gates
(plugin-tests, validate, catalog, markdownlint, shellcheck) cover every changed artifact class.

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

## Execution shape

Phase 1 is fully sequential in the main session — every step edits the same tightly-coupled skill
pair (SKILL.md ↔ reference ↔ scripts ↔ evals ↔ metadata), and total churn is well under the
parallelism-payoff threshold. Phase 2's execution shape is computed by its own architect pass.

| Phase | Surface | Basis |
|---|---|---|
| 1 (PR-A) | main session, sequential | coupled edits, judgment-heavy rewording |
| 2 (PR-B) | orchestrated lanes (per its architect) | script decomposition / reference rewrites / test porting are file-disjoint |
| 3 (cutover) | main session | live-loop + machine state, inherently serial |
| 4 (B16) | main session | issue-writing + user gate |

## Open questions

None for Phase 1. Phase 2 deferred questions (engine module boundaries, userConfig keys, eval
content, lint wiring, L3 mechanics) resolve at its architect pass; B16 naming/placement is
USER-RESERVED.

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

### Mechanical work

- One commit per plan step is not required; commit at green checkpoints with Conventional-Commit
  subjects; PLAN.md phase-tag updates ride the same commits.
- Sequential fallback: not applicable in Phase 1 (already sequential).
- PII gate before first commit: moved content is already public in-repo; new content carries no
  identities beyond the generic `gh api user` default.
