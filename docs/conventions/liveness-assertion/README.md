# Liveness assertion — false-green and healthy-while-dead surfaces

Owner doc for **whether a health, status, advisory, or gate surface may report success when the
capability behind it is dead or its findings are invisible**. One contract: a conforming surface
**fails loud** or **routes its findings into an agent-readable channel** — never both green and
silent. "Green-with-hidden-findings" and "healthy-while-dead" are contract violations.

The fleet already states slices of this doctrine in prose — [`PLUGIN-PHILOSOPHY`](../../PLUGIN-PHILOSOPHY.md)
[Prerequisites and failure behavior](../../PLUGIN-PHILOSOPHY.md#prerequisites-and-failure-behavior)
("No black boxes: a silently skipped feature is a defect"; "Do not swallow errors or claim success
when the promised result was not produced") — and enforces one mechanical slice in CI
(`silent-skip-gate` over `plugins/*/hooks/*.sh`). Under the
[convention registry](../../PLUGIN-PHILOSOPHY.md#convention-registry)'s one-owner-per-concern rule,
this doc closes the gap: a cross-surface contract for the **false-green** class that the hook-only
gate cannot reach
([melodic-software/claude-code-plugins#532](https://github.com/melodic-software/claude-code-plugins/issues/532)).

## Boundary

This doc owns the **liveness-assertion contract** — what "conforming" means when a surface reports
health, status, or a pass/fail verdict, and how findings must be routed so an agent can act on them.
It does not own:

- **Signal absent — never wired or invoked (#530).** A surface that produces no verdict at all —
  evals never run, a gate never invoked, a check omitted from the harness — is the adjacent-but-
  distinct class owned by
  [#530](https://github.com/melodic-software/claude-code-plugins/issues/530). Discriminator:
  #530 = signal *absent*; #532 = signal *false* (the check runs, reports green, and lies).
  Cross-link; do not merge.
- **Coupling and agnosticism (#531).** Whether a capability hardcodes a consumer-specific assumption
  is a different axis. A surface can be fully portable and still false-green; a coupling defect can
  exist on a surface that reports failure correctly. Cross-link only.
- **Hook prerequisite silent-skip (the `silent-skip-gate` slice).** A hook that quietly skips on a
  missing CLI is a *prerequisite-visibility* defect governed by
  [`hook-observability`](../hook-observability/README.md) and mechanically enforced by
  `scripts/check-silent-skips.sh`. That gate covers `plugins/*/hooks/*.sh` entry scripts only; this
  convention generalizes the *outcome* rule to health-check, advisory, and gate surfaces. The hook
  slice is a **conforming instance** of this contract, not its owner.
- **Per-surface mechanical fixes.** Instance issues (#510, #385, #465, and others below) own their
  remediation; this doc states the contract they conform to.

## The defect class

**False-green** — a surface reports success (green check, healthy status, pass verdict) while at
least one of these holds:

1. **Healthy-while-dead** — the capability the surface claims to verify did not demonstrably
   *execute*; only configuration, wiring, or process presence was checked.
2. **Green-with-hidden-findings** — the capability ran and produced findings, but those findings
   live only on a channel no agent reads (check-run annotations, a log file the harness never
   ingests, a stderr line discarded on exit 0).

This class is **review-agent-blind by construction**: a green check means nobody looks. The contract
exists because prose doctrine alone did not prevent instances from shipping.

## Core contract

Every health, status, advisory, or gate surface in scope must satisfy **at least one** of:

1. **Fail loud** — when the capability is dead, misconfigured, or its findings cannot be routed to
   an agent-readable channel, the surface exits non-success, blocks, or returns an explicit failure
   verdict. A "pass" must mean the capability ran and its outcome is trustworthy.
2. **Agent-readable channel** — when the surface is advisory or non-blocking by design, every
   finding it produces is published to a channel the harness, an agent, or CI tooling can read and
   act on without opening a human-only UI. Annotations-only, debug-log-only, or operator-console-only
   output does not qualify.

A surface that is green **and** silent about findings it produced is non-conforming. A surface that
reports healthy while the engine behind it is dead is non-conforming.

**Self-test probes for engines.** An engine health-check (setup `check`, a capability probe, a
result aggregator) must prove the capability *executes*, not merely that it is configured or that a
process name resolves. A conforming counter-example already exists in this repo: the hygiene lane runs
a `--self-test` on its own result aggregator before trusting it. Engine surfaces adopt that posture
on touch.

## Surface taxonomy

"Conforming" is stated per surface type. The types are not exhaustive; a new surface names the
closest type and states what it adds.

| Surface type | What "pass" must mean | Conforming when |
|---|---|---|
| **Engine health-check** | The capability demonstrably ran end-to-end, not only that binaries exist, env vars are set, or a daemon answered a ping that does not exercise the real code path. | Fail loud on dead engine **or** a self-test probe that executes the capability and surfaces failure; never "healthy" on configuration alone. |
| **Advisory lane** | Findings may not block merge, but they must not be invisible. | Every finding published to an agent-readable channel (e.g. SARIF uploaded to code-scanning per [#510](https://github.com/melodic-software/claude-code-plugins/issues/510)'s options). Annotations-only is non-conforming. |
| **Gate / classifier** | The verdict reflects the actual state read, not a wrong count or misread signal. | Fail-closed on ambiguity; never green when findings were miscounted or approval state was misread ([#465](https://github.com/melodic-software/claude-code-plugins/issues/465), [#499](https://github.com/melodic-software/claude-code-plugins/issues/499) — mechanical fixes tracked in [#534](https://github.com/melodic-software/claude-code-plugins/issues/534)). |

Placement of a CI meta-check (composite action in `ci-workflows` vs repo-local script like
`silent-skip-gate`) and per-surface self-test shape are implementation calls deferred to peel 2+;
this peel publishes the contract only.

## Relationship to existing doctrine and gates

| Existing surface | How it relates |
|---|---|
| [`PLUGIN-PHILOSOPHY` Prerequisites and failure behavior](../../PLUGIN-PHILOSOPHY.md#prerequisites-and-failure-behavior) | Prose doctrine this convention specializes for health/status/advisory/gate surfaces. Prerequisites section remains the entry point for runtime-absence classification; this doc adds the false-green class and surface taxonomy. |
| [`hook-observability`](../hook-observability/README.md) | Owns the three hook output surfaces (`statusMessage`, `systemMessage`, telemetry). Prerequisite-skip visibility is one *hook-shaped* instance of the core contract. |
| `silent-skip-gate` (`scripts/check-silent-skips.sh`) | Mechanical enforcement of the hook slice only. Not a stand-in for this convention. |
| Hygiene lane aggregator `--self-test` | Conforming counter-example for engine health-check — self-test before trust. |

## Adopters and instances

**A row is tabled only once a surface actually conforms.** Open instances stay in their tracking
issues until remediated; tabling a non-conforming surface would assert what the reader cannot rely on.

| Surface / instance | Status | Notes |
|---|---|---|
| `silent-skip-gate` over `plugins/*/hooks/*.sh` | Conforming (hook slice) | Enforces prerequisite-visibility on hook entry scripts; `# silent-skip-ok:` annotated exemption. Instance of core contract, not owner. |
| `loop-lane-floor-drift-gate` (`scripts/check-loop-lane-floor-drift.sh`) | Conforming (gate / classifier) | Replaced a prose claim that conformance was audited when nothing audited it. Fail-loud on every unresolvable input (exit 2): missing git or work tree, unreadable source, a marker matching zero or many times, a source block missing a floor bullet, or a discovery pass that cannot find the source it carries by definition. A repo-wide scan bounds its hand-maintained registry so the verdict covers the corpus rather than only the paths it was told about; `loop-lane-floor-carrier-ok:` is the annotated exemption, and a bare or stale one fails. |
| Hygiene lane aggregator `--self-test` | Conforming (engine counter-example) | Self-test before trusting aggregated results. |
| [#510](https://github.com/melodic-software/claude-code-plugins/issues/510) — zizmor advisory lane | Instance (non-conforming) | Advisory exits green; findings live in check-run annotations no agent reads. |
| [#385](https://github.com/melodic-software/claude-code-plugins/issues/385) / [#376](https://github.com/melodic-software/claude-code-plugins/issues/376) — disk-hygiene `setup:check` | Instance (non-conforming) | Reports healthy while engine is dead. |
| [#465](https://github.com/melodic-software/claude-code-plugins/issues/465) / [#499](https://github.com/melodic-software/claude-code-plugins/issues/499) — gate classifiers | Instance (non-conforming) | Green on misread state; mechanical fixes in [#534](https://github.com/melodic-software/claude-code-plugins/issues/534). |
| [#509](https://github.com/melodic-software/claude-code-plugins/issues/509) — security-review lane | Related | A review lane is only as good as the signals surfaced to it; depends on upstream surfaces conforming. |

Surfaces adopt this contract on touch: the next change to a health-check, advisory lane, or gate
states which taxonomy row applies and how it satisfies fail-loud or agent-readable routing.

## Enforceability

Classified per `melodic-software/standards` `conventions/engineering/enforceability-tiers.md`:

| Judgment | Tier |
|---|---|
| A health/status/advisory/gate surface satisfies fail-loud or agent-readable routing | **Reasoning-only** today — whether a probe proves *execution* vs *configuration*, and whether a channel is agent-readable, is a judgment about the surface's contract. |
| Hook prerequisite silent-skip | **Deterministic** — already enforced by `scripts/check-silent-skips.sh` for recognized shapes (the hook slice only). |
| CI meta-check for advisory lanes (e.g. SARIF publish) | **Detect-then-judge** when built — a lane can be flagged for missing publish step; judgment decides whether the channel qualifies. **Not built** in peel 1. |

**Peel 1 defers all new mechanical enforcement.** Recorded with event triggers rather than dates:

- **Basis** — `enforceability-tiers.md` routing rule (worth-mechanizing defaults to "not yet" until
  the contract exists); peel 1 publishes the contract only per
  [#532](https://github.com/melodic-software/claude-code-plugins/issues/532) decision brief Option A.
- **Recheck trigger (CI meta-check)** — peel 2+ lands a designed meta-check, **or** a second
  advisory-lane instance with annotations-only findings reaches `main` after this doc (the #510
  shape recurs without enforcement).
- **Recheck trigger (engine self-test gate)** — a third engine health-check instance with
  healthy-while-dead reaches `main` after this doc, **or** peel 2+ lands a repo-local self-test
  gate patterned on the hygiene aggregator counter-example.

## Versioning

This contract is versioned in [`CHANGELOG.md`](CHANGELOG.md). Changing the core contract, a taxonomy
row's conformance bar, or an enforceability verdict is a major bump; additive guidance or new
instance rows is a minor bump; docs-only clarification is a patch.

## External authority

- [`PLUGIN-PHILOSOPHY` Prerequisites and failure behavior](../../PLUGIN-PHILOSOPHY.md#prerequisites-and-failure-behavior) — prose doctrine this convention specializes.
- [`hook-observability`](../hook-observability/README.md) — hook-shaped visibility surfaces and the `silent-skip-gate` slice.
- `melodic-software/standards` `conventions/engineering/enforceability-tiers.md` — tier vocabulary and routing rule.
