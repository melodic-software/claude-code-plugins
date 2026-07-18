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

Interview-locked this round: join-key attribute namespace `autonomy.work_item.*` (OTel
app-name-prefix form; reverse-DNS structurally excluded by the fleet-name ban; migrates to any
future upstream work-item namespace per D3); join-key value = the item's canonical web URL,
attribute `autonomy.work_item.url` (globally unique across repos/trackers, derivable on both
sides; native short IDs collide multi-repo).

Prerequisite: WP1 implementation merged (`plugins/autonomy/` exists with `reference/` docs,
`skills/setup/`, and the contract-validator fleet-name gate). All phases sit on a fresh branch
cut after that merge; WP3's PR follows this package's PR (its convention doc cites this
contract — dead-link avoidance, same ordering rule as WP1's standards PR).

### Phase 1: Telemetry contract doc [TODO]

| File | Action | What changes |
|---|---|---|
| `plugins/autonomy/reference/telemetry.md` | Create | The T6 contract as tool-agnostic normative text: (1) every execution context class (interactive session, CI, autonomous runner) emits standard OTLP pinned to the OTel CI/CD + VCS semantic conventions — pin recorded as semconv release `v1.43.0` with `schema_url: https://opentelemetry.io/schemas/1.43.0` on every emission; attributes cited by registry reference, never hand-copied lists; RC caveat + reviewed-migration policy for upstream renames (D4). (2) The work-item join attribute: single custom attribute `autonomy.work_item.url`, value = the work item's canonical web URL in normalized form (the tracker's own canonical item URL: https scheme, no trailing slash, no query string or fragment) — string equality is the join operation, so the normalization rule is normative. Selection rule: the key is always the WORK ITEM's URL, never a PR/change URL; a change closing N items yields N per-item associations; an agent session keys on its leased item. Attribute SCOPE pinned per context: RESOURCE-scope on agent-session emission (so cost/token metrics and session spans all carry it), span-scope on the CI pipeline/task spans. Granularity guarantee: conforming autonomous dispatch runs ONE leased work item per emitting session/process (the trigger-layer lease contract is the guarantor); multi-item batch sessions get session-granular cost only — stated as a known limitation, not silently mis-attributed. Known join-epoch limitations stated normatively: repo rename/transfer and tracker migration change the canonical URL; the join is query-time, so sinks MAY remap historical values; a secondary immutable-ID attribute is deferred with trigger (rename churn proves material). Confidentiality clause: the attribute value inherits the confidentiality class of the referenced repo/tracker — any sink or artifact carrying it must enforce access controls at least as strict as the item's home. No other custom namespace; no-parallel-schema migration rule if upstream ships a tracker namespace; contract migrations (including the semconv-Stable rename wave when cicd/vcs graduate) are reviewed changes owned by the contract home, trigger recorded in the plugin's trigger register. (3) W3C TRACEPARENT propagation trigger → CI → agent session forms one causal tree; headless/CI-only property — interactive contexts explicitly excluded from inbound trace joining. Sink binding out of contract: three sink classes only (existing observability stack / OTLP-file-artifact free default with query-on-read / opt-in network backend), adapter obligations per class stated as shape, no vendor picks. Native-surface principle (D7): prefer each tool's native telemetry export; reimplementations of native surfaces are non-conforming. Telemetry-is-not-return boundary note (T5 seam). Zero vendor/fleet names — tool-specific mechanics live in SKILL.md. |

**Sanity Check:**

- `grep -c 'opentelemetry.io/schemas/1.43.0' plugins/autonomy/reference/telemetry.md` ≥ 1
- `grep -c 'autonomy.work_item.url' plugins/autonomy/reference/telemetry.md` ≥ 1
- Vendor+fleet deny-list grep empty over `reference/telemetry.md` (same token list as WP1 Phase 3)
- `grep -ci 'traceparent' plugins/autonomy/reference/telemetry.md` ≥ 1
- No hand-copied semconv attribute table: `grep -o 'cicd\.[a-z.]*' plugins/autonomy/reference/telemetry.md | wc -l` ≤ 4 (attributes named only as illustrative citations, never enumerated)
- `grep -c 'no trailing slash' plugins/autonomy/reference/telemetry.md` ≥ 1 (URL normalization rule present)
- `node scripts/validate-plugin-contracts.mjs` exit 0; lychee lane passes

### Phase 2: Guided-setup telemetry slice [TODO]

Extends the WP1 `setup` skill (discovery-first per D6/WP1 D7); all wiring lands as reviewable
changes; paid sinks advisory + explicit opt-in with cost surfaced. First work item — fresh-docs
mandate (repo CLAUDE.md): re-fetch the official skills + settings + monitoring docs before
editing SKILL.md or citing vendor env vars.

| File | Action | What changes |
|---|---|---|
| `plugins/autonomy/skills/setup/SKILL.md` | Modify | Add the telemetry slice to discovery + apply: detect an existing observability stack (config/env interview + repo inspection); wire emission toward it when found (env-block + CI snippet as reviewable changes); none found → free file-artifact default: CI pipeline spans via a minimal OTLP JSON-lines writer snippet AND agent-session signals via an ephemeral per-job collector (single static OSS binary + config template, receives the session's OTLP and writes JSON-lines into the same artifact directory — per-job, no standing infrastructure; this closes the session-capture path the agent CLI's exporter set cannot reach alone). No dependency on the stale community actions; the two live third-party actions are endpoint-push and stay named only as opt-in adapter examples. Hosted/paid sink → advisory + explicit opt-in, cost surfaced; free-default cost caveat surfaced consistently: artifact storage and per-job collector runtime are metered on private repos (same framing as the WP3 minutes caveat). Agent-session wiring MUST set the join attribute at resource scope (`OTEL_RESOURCE_ATTRIBUTES` carrying `autonomy.work_item.url` for work-item-dispatched sessions — verify the vendor honors it at implementation) alongside TRACEPARENT behavior and beta-trace flags; all vendor env vars documented here, not in `reference/`. Records the telemetry binding (sink class, endpoint/artifact path, semconv pin) as an ADDITIVE section of the WP1 schema-versioned binding — absent-section tolerance stated; no schema major bump for additive sections. |
| `plugins/autonomy/skills/setup/scripts/check-emission-conformance.*` (name/extension per repo script conventions) | Create | Minimal emission-conformance check adopters (and the Phase 3 demo) run against produced OTLP JSON-lines: `schema_url` present and pinned, join attribute present where required, value normalization holds. This is the contract's only enforcement surface — without it adopter drift is undetectable. |
| `plugins/autonomy/skills/setup/evals/evals.json` | Modify | Add telemetry-slice cases: existing-stack wiring path, no-stack file-artifact default, paid-sink advisory/opt-in refusal-to-default, non-interactive argument-supplied run extended with telemetry args. |
| `plugins/autonomy/skills/setup/templates/` (or the skill's existing snippet home from WP1 impl) | Create | CI emission snippet template(s): pipeline-span OTLP JSON-lines writer + artifact upload step shape, TRACEPARENT injection for headless agent steps. Template is surface-class-parameterized; fleet names banned. |
| `plugins/autonomy/README.md` | Modify | Shipped-capability list grows by the telemetry contract + setup slice; roadmap row flips from deferred. |
| `plugins/autonomy/.claude-plugin/plugin.json` | Modify | Description extends to shipped telemetry capability; minor version bump per repo convention. |

**Sanity Check:**

- `/skill-quality:check` + `validate-evals` pass (`skills_root` = `plugins/autonomy/skills`)
- `claude plugin validate --strict` exit 0
- `grep -ci 'file-artifact' plugins/autonomy/skills/setup/SKILL.md` ≥ 1 and `grep -ci 'opt-in' plugins/autonomy/skills/setup/SKILL.md` ≥ 1
- `grep -c 'OTEL_RESOURCE_ATTRIBUTES' plugins/autonomy/skills/setup/SKILL.md` ≥ 1
- Fleet-name sweep (`validate-plugin-contracts.mjs`) exit 0

### Phase 3: Conforming-path demonstration [TODO]

Acceptance-criterion probe: one path demonstrates a single trace tree trigger → CI → agent
session on the free default, zero paid dependencies. Scratch consumer repo (NOT this repo),
mirroring WP1's migration-gate step 9: a stub trigger step GENERATES its own root span and
propagates TRACEPARENT (the trigger hop is observed, not seeded); the Phase 2 writer snippet
emits the pipeline span into a single artifact directory; a headless agent session inherits
TRACEPARENT with `OTEL_RESOURCE_ATTRIBUTES` set, its OTLP captured by the Phase 2 ephemeral
collector into the SAME artifact directory; the Phase 2 conformance check runs against the
combined output; query via the DuckDB `otlp` extension (live-verified 2026-07-18). A small
sanitized OTLP fixture from this run is COMMITTED (plugin test-fixture home) as the durable
artifact the WP3 demo consumes — the PR-body transcript is evidence, not the interface.

Sink-class note: this demo exercises the FILE-ARTIFACT FREE DEFAULT class end-to-end. The
fleet's claude-ops collector/DuckDB pipeline is the existing-stack class's conforming
instance and is deliberately NOT used here — the scratch repo must not depend on fleet
plugins; no standing capability is created (near-duplicate audit rationale).

**Sanity Check:**

- DuckDB query over the single demo artifact directory returns exactly 1 distinct `trace_id` covering ≥ 3 spans (trigger root + pipeline + agent session)
- The same dataset shows an agent-session COST/token metric whose resource carries `autonomy.work_item.url` equal (string-identical) to the pipeline span's attribute value
- `check-emission-conformance` exit 0 over the demo output
- The committed fixture exists and the same DuckDB assertions pass against it
- Demo transcript + query output attached to the PR body; no paid service touched

### Phase 4: Gates [TODO]

Full in-repo gate run (same roster as WP1 Phase 5): `scripts/validate-plugins.sh`,
`scripts/run-plugin-tests.sh`, `node scripts/validate-plugin-contracts.mjs`,
markdown/typos/lychee lanes, `claude plugin validate --strict`, catalog regen check.
Near-duplicate audit statement: the telemetry slice composes claude-ops observability
(fleet's conforming sink instance) rather than duplicating it.

**Sanity Check:**

- All gate scripts exit 0
- `node scripts/generate-catalog.mjs` reports in-sync
- Near-duplicate audit statement present in the PR body

## Blast radius

MEDIUM — ~8 files in one plugin, but the contract doc constrains WP3–WP6, every future
adopter, and the join key WP3 depends on; new convention + cross-cutting observability
triggers match. Fully git-revertible; automated gates cover the shared surfaces.

## Stress-test summary

Step 3 fresh-context plan review: 11 findings (1 CRITICAL — the cost-join was undemonstrable:
attribute OTel scope unpinned, `OTEL_RESOURCE_ATTRIBUTES` unwired, demos joined against a
zero-cost pipeline span; all folded). Step 4 `/devils-advocate`: 3 CRITICAL / 4 HIGH /
4 MEDIUM / 1 LOW — folded: process-granularity guarantee + batch limitation; ephemeral
per-job collector closes the session-capture gap; join-key selection rule +
rename/transfer/tracker-move limitations + deferred immutable-ID trigger (user-locked: keep
URL); emission-conformance check + migration ownership; confidentiality clause;
observed-not-seeded trigger hop; committed durable fixture; consistent private-repo cost
caveats. Residual accepted: `OTEL_RESOURCE_ATTRIBUTES` reaching the vendor's metric exporter
is verify-at-implementation (divergence escalates); RC semconv pin accepted per D4.

## Execution shape

Fully sequential 1 → 2 → 3 → 4 — Phase 2 cites Phase 1's contract; Phase 3 exercises Phase 2's
snippets and conformance check; Phase 4 gates the authored tree. Parallel saving immaterial
(small volume, tightly coupled). Cross-package: this PR merges before the WP3 PR (WP3's doc
cites this contract; WP3's demo consumes this package's committed fixture); both wait on the
WP1 implementation PR.

| Phase | Surface | Basis |
|---|---|---|
| 1 | main-session | normative contract authoring, tightly coupled to T6 + interview locks |
| 2 | main-session | setup-skill + template judgment, vendor-doc re-fetch gate |
| 3 | main-session | scratch-repo runtime probe with divergence judgment |
| 4 | main-session | gate runs |

## Open questions

- Native-vs-hook telemetry audit + fleet dogfood wiring: backlog items to file via the
  work-items flow after this package lands (out of package per D1; trigger recorded).

## Decisions made (gate-passed)

| Decision | What it changes in the plan | Basis (evidence) |
|---|---|---|
| Contract doc filename `reference/telemetry.md` | Phase 1 target path | WP1 layout convention (concern-named docs, one per capability in `reference/`) + WP1's three shipped names |
| Semconv pin recorded as `v1.43.0` now, re-verified at build | Phase 1 pin + sanity check | Live releases API 2026-07-18; D4 makes /architect the arbiter |
| Free-default CI mechanics: hand-rolled OTLP JSON-lines writer + ephemeral per-job collector for session signals | Phase 2 deliverables; no third-party action dependency | Live verification: no official OTel action; artifact-pattern actions stale (2022/2023); live actions are endpoint-push; agent CLI has no file exporter |
| 1:1 process-per-item granularity guarantee + batch-session limitation | Phase 1 contract clause | Stress-test CRITICAL #1; trigger-layer lease contract (T1) is the guarantor |
| Join-key selection rule (work-item URL, never PR) + join-epoch limitations + deferred immutable-ID trigger | Phase 1 contract clause | Stress-test CRITICAL #3; user locked keep-URL 2026-07-18 |
| Confidentiality clause on the join attribute | Phase 1 contract clause | Stress-test HIGH #7 |
| Committed sanitized OTLP fixture as WP3's demo interface | Phase 3 output | Stress-test MEDIUM #10 |
| Two-PR ordering: WP2 merges before WP3; both after WP1 impl | Plan preamble + execution shape | WP1's dead-link-avoidance ordering precedent; WP3 cites this contract |

[FALLBACK — confirm or override] Emission-conformance check script as a NEW deliverable
(Phase 2) — invented beyond the Brief to close the stress-test governance gap (HIGH #6:
pinned contract with no enforcement surface). Flag if unwanted.

## Handoff to implementation

### User-approval gates

- The conformance-check script above is [FALLBACK] — surface before authoring if scope is
  contested.
- `OTEL_RESOURCE_ATTRIBUTES` not honored by the vendor's metric exporter at implementation →
  STOP and re-surface (the cost-join design depends on it; do not improvise an alternative).
- Any scope expansion beyond the four phases re-enters `/architect review`.

### Execution shape ([EXEC-SHAPE] tagged)

Sequential 1→4, all main-session (table above). PLAN.md phase tags advance in the same commit
as each phase; scratch-repo demo per Phase 3; divergence escalation applies to every phase.

### Mechanical work

Commit per phase on the implementation branch (suggest `feat/autonomy-telemetry`); gates re-run
in full at Phase 4; commits via the repo's commit conventions; PR body carries the demo
transcript + near-duplicate audit statement + this PLAN in a `<details>` block at close-out.
