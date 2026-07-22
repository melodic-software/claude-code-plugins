# Plan: #836 (PR B) — hook-observability fleet adoption

## Brief

Closes melodic-software/claude-code-plugins#836. PR A (merged, `72221a50fa`) landed the
`hook-observability` owner doc at `docs/conventions/hook-observability/README.md`. This PR
adopts its three surfaces across the fleet. Full design rationale lives in PR A's merged history
(PR #931) — this plan carries only what's needed to execute adoption; it does not re-derive
decisions PR A already locked and reviewed through 4 rounds.

## Locked scope (from the merged doc, not re-litigated here)

- **`statusMessage`**: add to all 27 wired `type: "command"` handler objects across 12 plugins'
  `hooks.json`. Config-only edit, present-tense gerund wording.
- **`systemMessage`**: 11 genuine gaps — 9 guardrails jq-missing/prerequisite-missing branches
  (convert to `hook::require_jq`, not raw `emit_skip_notice` — needs the once-per-session gate) +
  2 claude-ops skill-usage hooks (agent-only → dual-channel).
- **Telemetry**: 1 gap — `workflow-resilience-check.sh` has zero telemetry calls anywhere,
  including meaningful outcomes. Add at each meaningful exit; leave pure-inapplicability exits
  untouched (matches every sibling hook).
- **Gate correction**: `scripts/check-silent-skips.sh`'s `is_visible()` drops bare `>&2` as a
  sanctioned signal (verified in PR A: the only 9 fleet sites relying on that leniency are the 9
  systemMessage conversions above — safe to tighten in the same PR that fixes them). Flip the
  corresponding test fixture.
- **Housekeeping**: reconcile `docs/conventions/hook-telemetry/README.md`'s stale Implementers
  table.
- **Zero `lib/hook-utils.sh` edits** — every fix uses an existing helper
  (`hook::require_jq`, `hook::notice_once`, `hook::emit_skip_notice`, `hook::emit_telemetry`).

## Exact sites (from PR A's plan, re-verified against current main before editing)

### systemMessage — jq-missing → `hook::require_jq <event> "guardrails" "$INPUT"`

- `block-dangerous-git.sh`, `block-hook-bypass.sh`, `block-no-verify.sh`,
  `block-noncanonical-commit.sh`, `cli-flag-verify.sh` (jq-missing branch only),
  `flag-commit-pr-skill-bypass.sh`, `hardcoded-path-check.sh`, `secret-pattern-detection.sh`,
  `workflow-resilience-check.sh` (bundled with its telemetry fix).

### systemMessage — non-jq gap

- `cli-flag-verify.sh`'s bundled-verifier-missing branch: pair `hook::notice_once
  "guardrails-cli-flag-verifier" "$INPUT"` with `hook::emit_skip_notice` manually.

### systemMessage — agent-only → dual-channel

- `plugins/claude-ops/hooks/skill-usage-audit.sh`,
  `plugins/claude-ops/hooks/skill-usage-expansion-audit.sh`.

### Telemetry

- `plugins/guardrails/hooks/workflow-resilience-check.sh` — add `start=${EPOCHREALTIME}` near
  top, `emit_telemetry` call at each meaningful exit.

Re-verify every line-number citation against current `main` (PR A's merge and any other
concurrently-merged PR may have shifted them) before editing — do not trust PR A's plan's cited
line numbers blindly.

## Test plan

- `claude plugin validate --strict` per touched plugin.
- Each converted hook: extend or add `*.test.sh` with a jq-missing-path case asserting
  `systemMessage` non-empty (repro-first: must fail against the pre-fix hook, per
  `hook-precision`'s discipline, then pass after).
- `scripts/check-silent-skips.sh` + its test suite, post-tightening.
- `scripts/validate-plugin-contracts.mjs`.
- Full local gate sweep: hygiene, changelog-parity-gate (12 plugin version bumps), hook-utils-sync
  (expect no diff), silent-skip-gate, skill-quality-gate.

## Review history

Fresh-context independent code review (`review:code-reviewer` agent) found one real bug before
implementation was otherwise complete:

- **IMPORTANT — `notice_once` key collision silenced 8 of 9 guardrails jq-missing conversions.**
  All 9 sites initially passed the literal plugin id `"guardrails"` as `hook::require_jq`'s second
  argument. Since `require_jq`'s dedup key is `"${plugin}-jq"`, all 9 resolved to the identical key
  `"guardrails-jq"` — whichever guard ran first in a session silenced the other 8 for the rest of
  that session, on both channels, undermining the PR's own purpose. Not caught by any single-hook
  `*.test.sh` (each isolates its own `CLAUDE_PLUGIN_DATA`/session; none exercises two guardrails
  hooks sharing one session, the real-world condition). Fixed: each site now passes a hook-specific
  key (`"guardrails-block-dangerous-git"`, `"guardrails-cli-flag-verify"`, etc.), matching how
  `cli-flag-verify.sh`'s own separate bundled-verifier-missing key already avoided the collision.
  Added `plugins/guardrails/hooks/require-jq-notice-isolation.test.sh` — a repro-first regression
  test verifying (a) every `hook::require_jq` call site's key is unique (static, discovered not
  hand-enumerated) and (b) `hook::notice_once` fires independently for every real extracted key
  within one shared session/data-dir (runtime proof). Verified repro-first against a scratch copy
  with the collision reintroduced — the test correctly fails.

Every other reviewed area (buffer_stdin/require_jq reorder control flow in all 9 sites,
workflow-resilience-check.sh's telemetry composition with its pre-existing additionalContext call,
cli-flag-verify.sh's separate verifier-missing key, claude-ops's two skill-usage hooks, a sweep for
any missed jq-missing/agent-only conversions, CHANGELOG/version-bump accuracy across all 12
plugins, all 8 new telemetry schema files against their hooks' actual data shapes) was verified
clean — no other findings.

## Stress-test target (mandatory before implementation)

`hook::require_jq`'s dual-channel emission composing safely with each hook's *other* exit-0 JSON
output (advisory `additionalContext` in `cli-flag-verify.sh`, `workflow-resilience-check.sh`'s
existing `emit_additional_context`) — confirmed safe in PR A's stress-test (early-exit and
advisory paths are mutually exclusive) but re-verify against current `main`, not the PR A
snapshot, since main has moved.
