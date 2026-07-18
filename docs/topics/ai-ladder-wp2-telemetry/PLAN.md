# ai-ladder-wp2-telemetry

## Brief

### TLDR

Telemetry unification contract (T6): every execution context — interactive session, CI,
autonomous runner — emits standard OTLP pinned to the OTel CI/CD + VCS semantic conventions,
plus one contract-owned custom attribute carrying the work-item ID (the return-accounting join
key), with W3C TRACEPARENT propagation forming one causal tree per triggered chain. Sink
binding is deployment-owned and out of the contract. WP2 ships the contract doc and the
telemetry slice of guided setup.

### Goal

Any adopting org can reach the emitting state — all three execution contexts producing
semconv-conformant OTLP with the work-item join attribute and propagated trace context — via
guided setup, with zero paid dependencies on the default path, against whatever observability
stack the org already has (or the free file-artifact default when it has none).

### Locked decisions

| # | Decision |
|---|---|
| D1 | Package scope: WP2 ships (i) the telemetry contract doc and (ii) the telemetry slice of the guided-setup capability, both in the capability-distribution home (the ladder plugin per WP1 D4). Fleet dogfood wiring and the native-vs-hook audit execution are work-item backlog, out of package. |
| D2 | Contract pillars imported from T6 unchanged: (1) standard OTLP pinned to OTel CI/CD + VCS semconv; (2) one minimal custom attribute namespace carrying the work-item ID; (3) W3C TRACEPARENT propagation trigger → CI → agent session; sink binding deployment-owned, out of contract. |
| D3 | Work-item attribute lives in a single contract-owned neutral namespace — never per-adopter reverse-DNS (breaks cross-org queryability; forces per-deployment sink-adapter config). Exact token deferred to architect alongside the plugin naming pass. If upstream semconv later ships a work-item/tracker namespace, the contract migrates to it — the no-parallel-schema rule applies to our own addition. |
| D4 | Semconv pin policy: pin an exact semconv release and record `schema_url` on every emission. RC status accepted; upstream renames are handled as reviewed migrations, never silent. Exact version number resolved at build time against the live releases page. |
| D5 | CI-side emission default class: OTLP-file-as-artifact + query-on-read is the free default (OTLP File Exporter pattern; zero standing infrastructure, zero cost). A network OTLP endpoint (existing stack, self-hosted, or hosted) is an opt-in adapter, never default. Role split per WP1 D3: emission handler logic = CI-orchestration home; enabling settings = settings-as-code home. Exact exporter/action choice at architect, verified live. |
| D6 | Guided-setup telemetry slice is discovery-first per WP1 D7: detect an existing observability stack and wire emission toward it; none found → free file-artifact default; paid/hosted sink → advisory + explicit opt-in with cost surfaced (WP1 D6). All wiring lands as reviewable changes. |
| D7 | Contract carries the native-surface principle: prefer each tool's native telemetry export over reimplementing it; anything reimplementing vendor built-in telemetry is scrapped. The audit applying this to the first adopting instance (local collector/DuckDB pipeline, hook envelope vs native export) files via the work-item flow. |

### Constraints

- Any fleet repo name in normative contract text is a defect (WP1 acceptance criterion);
  fleet bindings live only in the binding-seam instance doc.
- Zero new cost by default; paid sinks advisory + explicit opt-in always.
- Telemetry is never presented as return — usage measures activity, not return (T5 boundary);
  return fields stay in WP3.
- Interactive sessions deliberately ignore inbound TRACEPARENT (verified vendor behavior);
  trace-tree joining is a headless/CI/runner property — the contract must not promise it for
  interactive contexts.
- Boris-alignment is the standing acceptance criterion: step-1 guardrail in its literal form
  (standard OTel into whatever stack exists), no step-skipping, trust before scale.

### Acceptance criteria

- Contract doc names roles and standard vocabulary only; semconv attributes referenced by
  pinned version + `schema_url`, never hand-copied lists.
- The work-item attribute is defined precisely enough that the WP3 Brief consumes it as the
  join key without reopening this contract.
- Guided setup takes an adopter with no observability stack to the emitting state on the free
  default path, as reviewable changes, with no paid dependency.
- One conforming path demonstrates a single trace tree across trigger → CI → agent session.
- No capability in the package reimplements a native telemetry surface.

### Captured assumptions

- Semconv RC is stable enough to pin against; rename migrations are manageable review-sized
  changes (evidence: githubreceiver v1.37.0 alignment).
- Boris artifact live-fetch failed this session (3x boot error); alignment verified against
  same-day verbatim captures in durable homes (#247 resolution comment, design-threads
  T5/T6). Re-fetch if any quote beyond those captures becomes load-bearing.
- Agent-CLI trace export remains beta; span shapes may change — contract pins signals and
  attributes, not beta span trees.
- All WP2 decisions recommendation-locked under explicit user pre-authorization
  ("go with your recommendation"), each grounded in same-day primary-sourced research.

### Out-of-scope (deferred with triggers)

- Fleet dogfood wiring (settings env blocks, CI workflow edits) — work-item backlog; trigger:
  WP2 build lands.
- Native-vs-hook telemetry audit execution — work-item backlog (carried seed); trigger: WP2
  contract text exists to audit against.
- Return-accounting fields, prompts, bands — WP3.
- Any sink backend recommendation or comparison — deployment-owned; guided setup surfaces
  classes (existing stack / file default / opt-in backend), never vendor picks.

### Deferred questions

- Exact custom-namespace token (with plugin naming pass) — `/architect`.
- Exact semconv release number to pin — `/architect` (verify live at build).
- CI exporter/action choice + collector config shape — `/architect` (verify live; community
  actions unofficial).
- Sink adapter shape catalog (existing-stack / file-default / opt-in-backend interfaces) —
  `/architect`.

## Plan

(unfilled — /architect)
