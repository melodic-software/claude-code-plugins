# Phase 2 design: engine module boundaries + config contract

Design record for PR-B (arbiter: /architect per Brief deferred-questions). Grounded in
`.work/babysit-prs-migration/map-snapshot-engine.md` (per-symbol targets) and
`map-source-skill-surfaces.md` (userConfig candidates); official plugins-reference fetched
2026-07-17 (userConfig `multiple: true`, `${CLAUDE_PLUGIN_DATA}` semantics, delivery limits).

## Module inventory (flat siblings, stdlib-only, `skills/babysit-prs/scripts/`)

| Module | Owns | Key resolution of map ambiguities |
|---|---|---|
| `babysit_util.py` | stdio UTF-8 config, JSON type helpers, `parse_timestamp`, `MIN_HEAD_SHA_PREFIX_LENGTH`, single `run_command` subprocess core | all three runners collapse here; timeout = param with flag override, no env; SHA-pin constant lives here so guard CLIs validate pins without a state import (recorded mixed-util exception — three ≤20-line concerns don't earn three modules) |
| `babysit_lease.py` | lease library: `lease_path`, acquire/heartbeat/release/reap cores, `require_owned_lease`, `load_lease`, `lease_expiry`, TTLs, steal-stale, `--repo` scope keying + snapshot↔lease pairing validation | map §2 shows four sibling CLIs import the lease surface — it is a library, not a CLI concern; deployed `--repo` lease scoping ports here (AC4) |
| `babysit_gh.py` | gh runner + JSON wrapper, field lists, ref parsing/validation, ONE parameterized discovery fn, `view_pr`, BLOCKED compare, REST fetchers/paginators, ONE GraphQL reviewThreads core, head-ref association | discovery axes: owners-search ∪ owners-repo-list vs explicit repos; paginator projections parameterized |
| `babysit_state.py` | state dir resolution (`--state-dir` flag → `CLAUDE_PLUGIN_DATA` env → error; empty/filesystem-root paths hard-error), lock, atomic write, projection, ledger merge, `save_state` + scoped-clear fix, SHA-pin resolution, persisted sweep counters | `save_state` takes `recommended_cadence` as a parameter — no state→delta import |
| `babysit_checks.py` | check enums, normalize/summarize/dedupe, `(typename, name)` identity keying, generic `classify_checks` | checks classification split from FB/DE; review-gate block extracted to trigger module; merge gate consumes same keying (fixes name-only dedup) |
| `babysit_feedback.py` | actor typing (structural primary), config-fed bot-login fallback (ships empty), verdict regexes, ONE review reduction (decisive = param), `review_commit_oid`, downgrades (config logins), `collect_feedback`, human stop, dependency-manager author detection | `KNOWN_BOT_LOGINS`/`CLAUDE_`/`CURSOR_REVIEWER_LOGINS` identity constants die; trigger module imports `review_commit_oid` from here |
| `babysit_review_trigger.py` | B11 generalized review-trigger + gate: trigger phrase defined ONCE (post + recognizer derive), request-state machine, evidence/reaction fetchers, review-gate block of `classify_checks`; dormant when unconfigured | kills two-file trigger duplication; `gate_state == "absent"` degrade preserved |
| `babysit_delta.py` | freshness classifier, fan-out constants + quiet-recheck, `classify_pr`, head-ref guard, 12 delta arms + NEW L3 foreign-activity arm (ledger vs same-login timeline diff → back off + contention report), cadence, `head_repository_scope` policy, advisory cap | policy seam parked in delta (consumers: classify, refresh CLI, review-trigger CLI) |

CLIs stay thin argparse shells (`manage_babysit_lease.py` shells over `babysit_lease`);
`babysit_merge.py`/`babysit_resolve_thread.py` import
`babysit_util`/`babysit_gh`/`babysit_checks` plus exactly one pure function
`babysit_feedback.is_dependency_author` — never snapshot/delta/state (SHA-pin constant lives in
util). Both guard CLIs take `--allowed-owners` csv (replaces `allowed_owners()`/`BABYSIT_OWNERS`)
and fail closed (exit 3) when absent. The merge CLI adds `--allow-dependency` and
`--allow-unprotected` overrides (both refused by default; the bin/ wrapper additionally rejects
`--allow-unpinned-head`). `request_codex_review.py` → `request_review.py`.
`_babysit_common.py` retired. State-dir resolution is flag-only (no env fallback).
`queue-state.json` carries `schema_version`; staleness guard + cadence are scope-aware.

## Guarded-wrapper contract (pinned for Lane D doc references)

`plugins/source-control/bin/source-control-babysit-merge` and
`plugins/source-control/bin/source-control-babysit-resolve-thread` — bare names are the ONLY
documented invocation for the two guarded mutations (interpreter-prefixed invocations broke
auto-mode allow rules — audit P1-4/P3-18). Wrappers self-locate the CLIs relative to their own
path, resolve the interpreter `py -3` → `python3` → `python`, set PYTHONUTF8=1, and emit a
clear degrade message when python is absent.

## userConfig delivery matrix (key → consumer)

Every key renders once in SKILL.md's substituted effective-config block (the only surface where
`${user_config.*}` / `${CLAUDE_PLUGIN_DATA}` expand — reference files are Read raw and use
placeholder-free `<slots>`). From there the agent passes explicit flags:

| Key | Flag | Consumer scripts |
|---|---|---|
| `watched_owners` | `--owners` (snapshot), `--allowed-owners` (guard CLIs, fail-closed) | snapshot, merge, resolve |
| `self_logins` | `--author` (snapshot), `--self` (seam readiness gate), unprotected-repo self-author exemption (merge) | snapshot, babysit-readiness-gate.sh, merge |
| `default_tier` | (prose only — selects skill mode on explicit invocations; never on auto-routed matches) | — |
| `merge_method` | `--method` | merge wrapper |
| `review_trigger_phrase` | `--trigger-phrase` | snapshot, request_review |
| `review_bot_logins` | `--review-bot-logins` | snapshot, request_review |
| `review_gate_context` | `--review-gate-context` | snapshot |
| `ci_gateway_context` | `--ci-gateway-context` | snapshot |
| `extra_bot_logins` | `--extra-bot-logins` | snapshot |
| `max_quiet_recheck_seconds` | `--max-quiet-recheck-seconds` | snapshot |
| `advisory_fix_round_cap` | `--fix-round-cap` | snapshot, feedback ledger |
| `worker_concurrency_cap` | (prose only — orchestration fan-out bound) | — |
| `worktree_root` | `--root` | prune; worktree-creation prose |

Multi-value serialization: csv assumed; Lane D's FIRST work item empirically smokes
`multiple: true` substitution shape and downgrades the keys to comma-joined single strings if
arrays don't substitute usably (recorded in `docs/extensibility-contract-smoke-tests.md`).

Single-org simplification (recorded limit): `review_*`/`ci_gateway_context` are user-global —
the first repo needing divergent contexts triggers moving them to the tracked
`.claude/source-control.md` seam.

## userConfig contract (all non-sensitive; skill-prose substitution → CLI flags)

| Key | Type | Default | Absent behavior |
|---|---|---|---|
| `watched_owners` | string, multiple | — | infer current repo owner |
| `self_logins` | string, multiple | — | `gh api user --jq .login` |
| `default_tier` | string | `safe` | — |
| `merge_method` | string | — | repo convention → squash |
| `review_trigger_phrase` | string | — | trigger module dormant |
| `review_bot_logins` | string, multiple | — | trigger module dormant |
| `review_gate_context` | string | — | gate absent-degrade |
| `ci_gateway_context` | string | — | gateway check unused |
| `extra_bot_logins` | string, multiple | — | structural detection only |
| `max_quiet_recheck_seconds` | number | 14400 | — |
| `advisory_fix_round_cap` | number | 100 | — |
| `worker_concurrency_cap` | number | 10 | — |
| `worktree_root` | directory | — | `${CLAUDE_PLUGIN_DATA}/worktrees` |

Lease steal/heartbeat windows (900/300) stay CLI-flag defaults — operator-tunable per invocation,
not identity/policy scalars; adding keys for them is sprawl without a driving need.

## Rejected alternatives

- **Package directory (`babysit/` with `__init__.py`)** — rejected: CLIs are invoked by path from
  skill prose; flat siblings keep `import babysit_state` working via script-dir sys.path with zero
  packaging machinery (matches current `import pr_queue_snapshot as snapshot` pattern).
- **Keeping guard scripts fully self-contained (zero shared imports)** — rejected: Brief's
  improvement backlog mandates collapsing duplicate paginators/runners; auditability preserved by
  restricting guard imports to the read-only fetch/check modules.
- **Baking current fleet values as userConfig defaults** — rejected: zero baked identities (B5);
  dormant-by-default review-trigger module is the honest generalization.
- **pyright/ruff CI lane in ci-workflows** — out of scope (Brief); ruff runs opportunistically in
  `engine.test.sh` (self-SKIP), pyright gap recorded in PR body.
