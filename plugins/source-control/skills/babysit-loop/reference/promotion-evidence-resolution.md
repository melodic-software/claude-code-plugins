# Promotion-evidence resolution (merge lane)

This lane's binding of the guardrail contract's promotion-state ceiling for the rung partition
(`SKILL.md` cycle-shape step 3). The bound `promotion_state` on a security binding is a **ceiling
only** — consumers must resolve each promotable cell's **effective** state against live
promotion-evidence telemetry before every autonomous merge decision, fail-closing to unpromoted
when evidence is unavailable, untrusted, partial, or forgeable
([`guardrails-security-binding.schema.json`](../../../../autonomy/skills/setup/schemas/guardrails-security-binding.schema.json)
`promotion_state` description;
[`verification-topology.md`](../../../../autonomy/reference/guardrails/verification-topology.md)
"Consumers resolve both"). Reading the bound state alone is non-conforming.

## Promotable cells and rung mapping

| Effective merge rung | Work classes the rung admits | Promotable cell(s) that must be effective-promoted |
|---|---|---|
| `c2-mechanical` | C2 mechanical only | `C2-auto-merge` |
| `c3-autonomous` | C2 and C3 | `C2-auto-merge`, `C3-auto-merge` (and `C3-ai-review-blocking` as a prerequisite of `C3-auto-merge`) |
| `full-autonomy` | every class up to C3 | same as `c3-autonomous` for C2/C3; still never C4/C5 |
| `human-only` | none | none — promotion resolution is skipped (eligible set empty) |

`C4/C5` merge never promotes; no cell covers them.

## Trusted seam (required)

Promotion evidence MUST be resolved through a **trusted seam** — an agent-unwritable bootstrap
outside the target repository's blast radius, the same class of surface the autonomy setup skill
names for security-binding resolution
([`setup/SKILL.md`](../../../../autonomy/skills/setup/SKILL.md) "Agent-unwritable bootstrap for
security resolution"). Evidence read from repo-local, agent-writable, or otherwise forgeable
surfaces does **not** qualify: partial reads, stale snapshots, and operator-supplied JSON without
provenance are treated as **unavailable** and fail-closed.

The canonical resolution algorithm — bound ceiling, epoch-scoped contrary events
(`gate-failure`, `reverted-merge`, `verification-divergence`), prerequisite propagation — is owned
by [`check-security-binding.mjs`](../../../../autonomy/skills/setup/scripts/check-security-binding.mjs)
evaluation mode (`--evidence`). The loop lane invokes that resolution **through the trusted seam
only**, never by re-deriving a subset in prose.

**Phase note (#1695).** The full three-arm resolver (gh-native evidence arms, epoch pinned to the
run-level raising commit) is not yet wired on this seam. Until the seam returns a qualified,
non-forgeable evidence read, **every promotable cell resolves effective-unpromoted** — autonomous
merge stays off for C2/C3 classes regardless of tracked rung. Operators keep `--merge human-only` on
launch lines until both this seam qualifies and the repository's suggested evidence predicates are
met ([`loop-lane-prompts.md`](../../../../../prompts/loops/loop-lane-prompts.md) merge-lane
copy-blocks).

## Fail-closed rules

Resolve once per cycle immediately before the work-class rung comparison, after the effective merge
rung is known and before any PR enters the merge-eligible set.

| Condition | Effective state | Partition effect |
|---|---|---|
| Trusted seam unavailable (no bootstrap, read error, timeout) | every cell → unpromoted | no C2/C3 PR is merge-eligible on promotion grounds |
| Evidence untrusted, partial, or forgeable | every cell → unpromoted | same |
| Contrary event in epoch for a cell | that cell → unpromoted | classes requiring that cell excluded on the **next** cycle without config change |
| Prerequisite cell unpromoted | dependent cell → unpromoted | e.g. C3 excluded when `C2-auto-merge` demoted |
| Cell bound unpromoted with clean evidence | unpromoted | class excluded |
| Cell bound promoted, no contrary in-epoch evidence | promoted | class may proceed to work-class + other withholdings |

Report the resolution source, each cell's bound→effective pair, and any fail-closed reason in the
cycle-start config report. Never treat a demotion as a standing rung lower — it is telemetry-driven
exclusion for the affected class only.

## Partition interaction

Promotion resolution is a **gate on top of** the existing rung partition, not a substitute for it.
A PR still requires close-linked work item, label-enforced class, C4/C5 floor, do-not-merge veto,
human blocking feedback withholdings, and every other step-3 rule. Effective-unpromoted
`C2-auto-merge` makes a C2-mechanical PR ineligible exactly as if the rung were too low — routed to
the `safe` per-PR pass, never a merge-capable invocation.
