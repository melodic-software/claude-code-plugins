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

*(empty — /architect fills this per phase)*
