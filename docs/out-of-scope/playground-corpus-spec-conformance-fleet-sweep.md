# Playground corpus: fleet spec-conformance sweep (V3)

## Decision

**Parked — needs human.** This repository does not run an autonomous fleet sweep of every
`SKILL.md` against the Agent Skills standard ([#3612](https://github.com/melodic-software/claude-code-plugins/issues/3612)).

**Claim:** spec-conformance acceptance for the full skill fleet (interop questions, `compatibility`
field policy, YAML colon defects beyond `skill-quality:check`) is operator-owned, not an agent
lane. **Basis:** ADR 0026 deferred corpus vertical V3 with issues #3612–#3616; mechanical overlap
already lives in `skill-quality:check` and `check-skill.sh`. **As of:** 2026-09-28. **Recheck:**
operator unpark of #3612, completion of #3617 pilot learnings, or a second regular contributor
requesting the sweep.

## Rationale

- Acceptance requires recorded decisions per interop question (frontmatter stripping, compaction,
  `.agents/skills/` portability) that a grep-only pass cannot settle.
- A priced fleet sweep is explicitly out of band for autonomous drain work; partial fixes without a
  human findings report would re-litigate the same gaps.

## Revisit when

- The #3617 user-run pilot produces a findings template the operator adopts, or
- A maintainer unparks #3612 and schedules the sweep.

## Prior requests

- #3612 (2026-09-28): deferred vertical from playground-integration corpus; drain shipper parks
  with this ledger entry (no fleet sweep executed).
