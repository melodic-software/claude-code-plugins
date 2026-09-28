# Fleet-wide model-invocable prerequisites check

Recorded park for
[#4240](https://github.com/melodic-software/claude-code-plugins/issues/4240).
Missing external tools (hook binaries such as `markdownlint-cli2`, `biome`,
`goimports`) are not surfaced to the user in the main conversation. The ask
is a model-invocable fleet-wide prerequisites check that never auto-installs.

## Decision

**Park until funded.** Do not add a `deps` action, a new skill, or a
manifest `prerequisites` block from this record.

- **Option A (taken):** park the model-invocable fleet prerequisite skill.
  Per-plugin `*:setup check` stays `disable-model-invocation: true`. Hook
  notices stay as they are. Never install, never download, never `npx`.
- **Option B (declined):** implement the fleet check now, including the
  home (claude-ops:plugins `deps` vs machine-health:audit), the declaration
  format, dropping `disable-model-invocation` on `check`, and re-keying
  `hook::notice_once` so a subagent skip reaches the parent.

**Claim:** there is no model-invocable fleet-wide prerequisites check. Setup
`check` stays human-only. Missing-tool notices that fire in a subagent do
not become a parent-context ask to install. That skill is parked.
**Basis:** #4240 (operator posture: surface loudly, never auto-install).
`docs/conventions/invocation-mode/README.md` class (ii): setup skills carry
`disable-model-invocation: true`; a `true` skill cannot be invoked by any
other skill. Counted 2026-09-28: 58 plugin-level
`plugins/*/skills/setup/SKILL.md` files, all `true`.
`plugins/claude-ops/skills/plugins/SKILL.md` has actions `sync`, `audit`,
`converge`, no `deps`. `hook::notice_once` keys the marker on session and
agent id (`plugins/guardrails/hooks/hook-utils.sh`). #4666 is parked on the
same gate (machine-profile orchestration needs this unblock).
**As of:** 2026-09-28.
**Recheck:** a maintainer funds the fleet check and records (1) where it
lives, (2) the machine-readable declaration format, and (3) whether
invocation-mode class (ii) is amended so `check` is model-invocable while
`apply` stays hidden.

## Rationale

- Home and declaration format are open decisions. Shipping one without the
  other drifts.
- Relaxing `disable-model-invocation` on every setup `check` is a fleet
  contract change (58 skills plus `validate-plugin-contracts.mjs`), not a
  docs patch. #4666 already declined that split until this issue records it.
- Auto-install is ruled out by the operator.

## Revisit when

- a maintainer funds the check and records the three decisions above, or
- invocation-mode class (ii) is amended so a `check` action can be
  model-invocable.

## Prior requests

- #4240 (2026-09-28): needs-human; Option A recorded here.
- #4666: machine-profile park; recheck waits on this issue.
