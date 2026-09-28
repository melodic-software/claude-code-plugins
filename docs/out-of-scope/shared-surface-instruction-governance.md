# Shared-surface instruction governance

## Decision

**No** — this repository does not ship a cross-repo convention for per-surface ownership,
precedence between contributors, or how a consuming team records adjudications when multiple
authors' standing instructions meet on one shared surface.

## Rationale

- The repo is single-operator today. A multi-contributor governance convention has no cases to
  run against here and would be authored from imagination rather than friction.
- `claude-config:audit-instructions` check **I15** already detects conflicting instruction
  *pairs* across surfaces. Ownership only becomes live when two people write to the same surface.
- `docs/conventions/instruction-exception-register/` governs which instructions may be
  *deleted*, not who *owns* a shared surface. Adopting it as the ownership answer is a misread
  (#3568).

## Revisit when

- A second regular contributor writes to a shared instruction surface in this repository, or
- A consuming team reports an adjudication conflict that I15 surfaces but cannot resolve.

## Prior requests

- #3568 (2026-09-28): context-engineering integration contract Q8 (G-GOV); defaulted to this
  rejection per maintainer triage on the issue thread.
