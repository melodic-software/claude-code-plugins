# context-budget: unpaid interactive and billing measurements

## Decision

**Parked — unpaid.** This repository does not run the two designed-but-unexecuted
`context-budget` probes ([#2954](https://github.com/melodic-software/claude-code-plugins/issues/2954)).
The report contract keeps its current hedges.

**Claim:** interactive-session deferral eligibility and deferred-tool `count_tokens` billing stay
unmeasured; both probes need a funded host this lane does not have (a real TTY for `/context`,
and an Anthropic API credential for `count_tokens`). **Basis:** #2954 probe designs; triage
2026-09-06 (capability gate: no TTY, `x-api-key header is required`); live wording in
`plugins/context-budget/skills/audit/reference/report.md` (Stamp `sessionKind: headless`; Headline
"recurring request weight outside the window") and
`plugins/context-budget/skills/audit/reference/engine.md` "Session-kind boundary". **As of:**
2026-09-28. **Recheck:** an operator funds a probe host with an interactive terminal and an API
credential and unparks #2954.

## Rationale

- Probe 1 diffs interactive `/context` against a same-cwd/binary/settings headless
  `measure.mjs snapshot`. A headless agent cannot produce the interactive half.
- Probe 2 needs two `count_tokens` calls that differ by one `defer_loading: true` tool
  definition. No unpaid lane holds that credential, and the authoring container did not either.
- The hedges already in the report contract are honest. Replacing them without numbers would
  invent a measurement.

## Revisit when

- An operator funds a probe host (interactive TTY plus API credential) and unparks #2954, or
- A Claude Code or API release note changes deferred-tool send semantics or `/context`
  session-kind behavior enough to invalidate the current hedges on documentation alone.

## Prior requests

- #2954 (2026-09-28): two open measurements from the context-budget topic slice; drain shipper
  parks with this ledger entry (neither probe executed).
