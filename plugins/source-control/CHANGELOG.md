# Changelog

All notable changes to the `source-control` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.9.2]

### Fixed

- **babysit-prs no longer re-dispatches a worker onto its own prior-round replies.** For a solo
  maintainer whose `gh` login is the configured self-login (`gh api user` login plus any
  `babysit_self_logins` extras), the delta engine counted the worker's own classification replies
  and `Fixed in <sha>` follow-ups as new human-authored feedback, manufacturing a self-inflicted,
  unsuppressible `new_human_blocking_feedback` dispatch that re-fired every cycle with zero real
  work. The `new_human_blocking_feedback` and `new_human_feedback` deltas now exclude items
  authored by the configured self-login(s) — the same self-reply exclusion `review-discipline.md`
  §1 already mandates for the worker, and parity with the bot delta arms (self-filtered
  structurally because the engine never comments as a bot). Scoped to the dispatch deltas only: a
  self-authored item still classifies as human feedback, so a genuine "do not merge" comment the
  maintainer posts under their own login keeps the human stop and triage blocker intact and still
  halts the merge gate.

## [0.9.1]

### Fixed

- **babysit-prs review-trigger head-staleness hardening** (dormant-by-default module; no effect
  until `babysit_review_trigger_phrase` + `babysit_review_bot_logins` + `babysit_review_gate_context`
  are configured).
  - **F7** — `request_review.py`'s pre-POST freshness guard rejected only the literal `BEHIND`
    merge state. A head that is behind its base but reports `BLOCKED` (GitHub masks `BEHIND` behind
    `BLOCKED`) slipped through and spent the one-shot review request on a stale SHA. The guard now
    reuses the compare-confirmed freshness signal (`compute_branch_freshness`, off the
    `_blocked_base_compare` enrichment `view_pr` already computes), so a compare-behind head is
    rejected and the branch-refresh flow runs first.
  - **F8** — the candidate predicate in `babysit_review_trigger.py` blocked candidacy whenever *any*
    reviewer reaction existed. Reactions carry no commit SHA, so a reaction left on an earlier head
    persisted onto later heads and permanently suppressed the new head's observation window. The
    check is now scoped to reactions associated with, or newly observed for, the current head.
  - **F8 follow-on** — the F8 scoping stopped at the candidate predicate: `request_review.py`'s
    posting guard (`validate_current_candidate`, both its pre-POST check and its post-POST
    concurrency check) still gated on the raw, unscoped reaction list. A PR made eligible by the F8
    fix because its only reaction was stale (an earlier head) would still have every request attempt
    rejected at posting time, recorded as `"ambiguous"`, and blocked from retrying. The scoping rule
    is extracted into a shared `resolve_associated_reactions` helper in `babysit_review_trigger.py`
    and applied at both the candidate predicate and every posting-guard reaction check.

## [0.9.0]

### Changed

- **`/source-control:setup` adopts the uniform setup contract** (fleet conformance wave). The skill
  now splits into a read-only `check` action (default) and an `apply` action across both
  configuration surfaces. `check` reports the effective commit-subject / PR-title convention (from
  the tracked `.claude/source-control.md`) and the babysit-prs `userConfig` surface (effective
  config, branch-protection posture, Windows long paths) — treating an unconfigured surface as INFO
  (the Conventional Commits / inference default; the safe babysit tier) and FAILing only a
  configured-but-broken convention (a non-machine-checkable `subject_pattern`, or a
  `.claude/source-control.md` excluded by `.gitignore`). The previous interactive convention
  interview becomes `apply`'s interview path, run when no arguments are supplied; `apply
  subject_pattern=<anchored-regex | 'Conventional Commits'>` now writes the convention
  non-interactively. The repo-root anchoring and the git-ignore / staging verification of the written
  file are preserved unchanged.
- The babysit reconfigure guidance is corrected to the fresh-install-only semantics of `--config`:
  interactive `/plugin configure source-control` any time; headless requires
  `claude plugin uninstall source-control` then reinstalling with `--config KEY=VALUE`. Reconfiguring
  `userConfig` is not visible to the running session, so verification defers to a fresh session
  rather than reporting a false failure.

## [0.8.1]

### Changed

- README now declares the full runtime (prerequisite-visibility wave): `jq`
  and Bash (Git Bash on native Windows) alongside `git`/`gh`, plus the
  `unzip` requirement of the CI-log fetch path with its documented
  stop-with-remediation behavior. Script behavior is unchanged — the gates
  already existed at point of use.

## [0.8.0]

### Added

- **`/source-control:babysit-prs` capability convergence.** The skill gains opt-in `worker` and
  `autopilot` tiers on top of the safe default: `worker` auto-resolves outdated bot threads and
  merges PRs the deterministic gate proves ready; `autopilot` widens author and thread scope
  under the watched owners. Both merge only behind `babysit_merge.py`'s gate — `mergeStateStatus
  == CLEAN` cross-checked, head-SHA pinned, never `--admin`, never force-push.
- **Decomposed Python engine** under `skills/babysit-prs/scripts/` (stdlib-only): `babysit_util`,
  `babysit_gh` (one parameterized discovery function, one reviewThreads paginator), `babysit_state`
  (scope-aware, schema-versioned, corrupt-state quarantine), `babysit_lease` (`--repo` scoping +
  snapshot pairing), `babysit_checks`, `babysit_feedback`, `babysit_review_trigger` (bot-agnostic,
  config-driven, dormant when unconfigured), `babysit_delta` (classification + fan-out + L3
  foreign-activity detection). Thin CLIs: `pr_queue_snapshot`, `babysit_merge`,
  `babysit_resolve_thread`, `manage_babysit_lease`, `manage_feedback_ledger`,
  `prune_babysit_worktrees`, `refresh_pr_branch`, `request_review`. Relocated + reorganized test
  suite runs in the plugin-tests lane (`engine.test.sh`, self-SKIP when Python is absent). Python
  3.11+ is a declared prerequisite for the `worker`/`autopilot` tiers only; the safe default runs
  Python-free.
- **First-in-fleet plugin `bin/` wrappers** — `source-control-babysit-merge` and
  `source-control-babysit-resolve-thread` expose the guarded mutations as bare commands whose
  allow rules survive auto mode; the merge wrapper refuses `--allow-unpinned-head`.
- **15 `babysit_`-prefixed `userConfig` keys** (watched owners, self logins, default tier, merge
  method, the bot-agnostic review-trigger settings, bot-login fallbacks, downgrade-reviewer logins,
  cadence and fan-out bounds, worktree root) plus a babysit check/apply section in
  `/source-control:setup`. `babysit_self_logins` unifies with and extends the additive key
  introduced in 0.7.0: it composes on your `gh api user` login as the self set for discovery scope,
  readiness-gate rows, and the merge-gate self-exemption.

### Changed

- **Breaking:** the safe default narrows discovery from every open PR to your own PRs under the
  current repository's owner (own-authorship boundary; Dependabot/dependency PRs are held from
  merge in every tier). `worker`/`autopilot` widen scope explicitly.
- State root moves from `CODEX_HOME` to `${CLAUDE_PLUGIN_DATA}`; all engine configuration is now
  delivered via CLI flags substituted from the SKILL.md effective-config block.
- Self-identity is additive across every consumer — `--extra-self` (readiness gate), `--author
  @me,<extras>` (discovery), and `--self-logins @me,<extras>` (merge gate) each fold the configured
  `babysit_self_logins` extras onto your gh login.

### Fixed

- Multi-login discovery queries `--author` once per login and unions the results (a comma-joined
  value matched no one, silently dropping owned PRs for multi-login users).
- Review-trigger candidacy no longer stalls forever when no CI gateway context is configured (the
  documented gateway-unused fallback).
- Snapshot state honors a `~`-prefixed `--state-dir`, sharing the resolved path with the other
  engine CLIs instead of writing under a literal `./~/…` directory.
- The merge gate recognizes your own PRs on unprotected bases (self logins are passed through),
  no longer requiring the interactive `--allow-unprotected` override for own-authored PRs.

### Removed

- The `BABYSIT_*` environment-variable seams on the Python engine (owners, timeouts, quiet-recheck
  window) — replaced by CLI flags fed from `userConfig`. The shared readiness gate's `--self`
  (full override) / `--extra-self` (additive) contract is unchanged.

## [0.7.0]

### Changed

- **Personal tuning scalars migrated to native `userConfig`** (the fleet-wide kill-switch/scalar
  doctrine ruling): `worktree_stale_days` (default 14), `babysit_self_logins` (csv, default
  empty), and `fetch_logs_max_bytes` (default 52428800). The skills substitute the values into
  their own content; `babysit-readiness-gate.sh` gained an additive `--extra-self` flag (the
  `--self` full-override flag is unchanged) and `fetch-failed-logs.sh` gained `--max-bytes`.
- **BREAKING:** the `WORKTREE_STALE_DAYS`, `BABYSIT_SELF_LOGINS`, and `FETCH_LOGS_MAX_BYTES`
  environment variables are retired and no longer read; re-express any non-default value as the
  matching `userConfig` option. `FETCH_LOGS_SCRATCH` / `FETCH_LOGS_REPO` are unchanged.
  Zero-config behavior is identical.

## [0.6.0]

### Added

- **New `/source-control:babysit-prs` skill** — the all-PR self-pacing babysit loop, extracted
  from `/source-control:pull-request` into its own skill (distinct discovery intent: fleet loop
  vs single-PR lifecycle). Same behavior as the former `babysit` action: discovers every open
  non-draft PR oldest-first, checks each out, keeps branches fresh, classifies every review
  finding with GitHub-verified evidence, fixes valid findings, reports readiness. Never merges.
  Invoke via `/source-control:babysit-prs` (loop pairing: `/loop /source-control:babysit-prs`).
- **Plugin-scope shared review discipline** at `reference/review-discipline.md` — the canonical
  home of finding extraction (with the mandatory ≥3-finding subagent dispatch), per-finding
  D1–D7 verification gates, and self-reply filtering, cited by both `pull-request` and
  `babysit-prs` instead of duplicating the rules per skill.

### Changed

- **Breaking:** the `babysit` action is removed from `/source-control:pull-request` — use
  `/source-control:babysit-prs`. The pull-request description, action table, phase table, and
  checklists no longer carry babysit content; `reference/monitor.md`'s cross-references into the
  former babysit reference now cite the plugin-scope review discipline.
- Shared scripts hoisted from `skills/pull-request/scripts/` to plugin-root `scripts/`
  (`fetch-all-pr-comments.sh`, `babysit-readiness-gate.sh`, `test-helpers.sh`, with their
  tests) — cited by both skills via `${CLAUDE_PLUGIN_ROOT}/scripts/`.

### Removed

- `discover-prs.sh` (+ test) — retired; the inline `gh pr list` filter in the babysit-prs
  reference is the discovery contract.

## [0.5.2]

### Fixed

- `/pull-request create`'s worktreeinclude sync check no longer reports phantom `CHANGED:` lines
  for `.worktreeinclude` patterns that match no files — an unmatched glob stays a literal string
  in Bash and previously fell through to the changed-file branch; it is now skipped.

## [0.5.1]

### Changed

- References to the renamed `/toolchain:build` skill now invoke `/toolchain:check` (toolchain 0.2.0 breaking rename). Version bumped so existing installs pick up the rewritten prompts.

## [0.5.0]

### Added

- **Exec-bit check in `/source-control:commit`.** Immediately after staging, newly-added files whose
  first line is a shebang (`#!`) are checked against the index and fixed with
  `git update-index --chmod=+x` when staged non-executable. Closes the gap where a new `.sh`/`.py`
  script lands as mode `100644` and is only caught by a CI exec-bit lint lane after the push
  round-trip. Runs after the format-before-push check below (not before), because re-staging a
  formatter's fixes reads the worktree file mode and would otherwise silently undo an
  already-applied `--chmod=+x`.
- **Format-before-push check in `/source-control:commit`.** Before drafting the commit message, the
  skill now checks the consuming repo for an already-configured formatter/linter (`package.json`
  scripts, `biome.json`, a `Makefile` target, `.editorconfig` + `editorconfig-checker`, or an
  equivalent repo-native tool) and runs it against the files staged for that commit, re-staging any
  fixes. Scoped to this commit's paths, not the full index, so it never mutates or blocks on staged
  work outside this commit's scope. Runs only tooling that already exists in the consuming repo;
  skips silently when none is discoverable.

## [0.4.1]

### Fixed

- Require a branch-derived issue to be open before adding `Closes #N`, preserve
  merge-commit branch history when integrating the default branch during PR
  babysitting, and stash a dirty worktree before reusing it for the next task.

## [0.4.0]

### Added

- `/source-control:setup` skill: interviews the repo and writes the tracked
  `.claude/source-control.md` commit-subject / PR-title convention config —
  inferring first from the repo's own `CLAUDE.md`/rules, commit-msg hook, or
  git log history before asking. Offers Conventional Commits (11-type
  vocabulary) as the recommended default, or a custom pattern for orgs that
  don't use Conventional Commits. Re-runnable to reconfigure. Ships evals.

## [0.3.1]

### Changed

- Synced the pull-request verify-gate example to the reorganized taxonomy:
  `/verify-changes` / `/build` are now `/verification:confirm` / `/toolchain:build`.

## [0.3.0]

### Added

- `/resolve-conflicts` skill: intent-first resolution of in-progress merge/rebase/cherry-pick
  conflicts — both sides' history read before any hunk is edited, compose-by-default with
  evidence-gated side-dropping, a post-resolution semantic-conflict sweep (build/tests before
  done), and a hard never-`--abort` discipline. Ships three evals.

## [0.2.0]

### Added

- Readiness security-gate, mixed-actor, and three worktree evals.
