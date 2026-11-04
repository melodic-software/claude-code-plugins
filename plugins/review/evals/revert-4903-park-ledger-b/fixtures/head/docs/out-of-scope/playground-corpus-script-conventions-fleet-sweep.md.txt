# Playground corpus: script-conventions fleet sweep (V6)

## Decision

**Parked — needs human.** This repository does not run an autonomous vertical sweep of bundled
`scripts/` trees against the Agent Skills using-scripts checklist
 ([#3615](https://github.com/melodic-software/claude-code-plugins/issues/3615)).

**Claim:** script-conventions acceptance (non-interactive CLI shape, structured stdout, idempotency,
dry-run, exit codes, and a recorded house position on PEP 723 vs vendored deps) requires
per-script human judgment across high-use plugin directories. **Basis:** ADR 0026 deferred corpus
vertical V6 with issues #3612–#3616; scope names claude-ops, planning, knowledge, and
skill-quality first. **As of:** 2026-09-28. **Recheck:** operator unpark of #3615 or a maintainer
schedules the sweep with an explicit directory list.

## Rationale

- Checklist verdicts and dependency-policy decisions are not safely batch-applied without reading each
  script's invocation context (hooks, CI, fleet hosts).
- Cheap inline fixes belong in a human-led pass that files per-script findings, not in an unattended
  fleet run.

## Revisit when

- A maintainer unparks #3615 and names the first script directories to audit, or
- A consuming team reports a recurring scripts checklist violation fleet-wide.

## Prior requests

- #3615 (2026-09-28): deferred vertical from playground-integration corpus; drain shipper parks
  with this ledger entry (no fleet sweep executed).
