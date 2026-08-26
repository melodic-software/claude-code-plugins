# Routine slice

One slice of the `apply` action in [`../SKILL.md`](../SKILL.md), selected by argument and run only
when `apply` reaches it. Like the guardrail slice it prepares the security surface and never writes
it.

Wires the standing-routine state of the
[routine catalog](${CLAUDE_PLUGIN_ROOT}/reference/routines.md): a routine is a scheduled
`temporal`-class signal adapter behind the governed queue, never a private execution or merge
path. This slice is discovery-first and detect-diff-reconciles against the org's EXISTING
schedulers and bots. Everything free lands as reviewable changes; paid or preview scheduling
surfaces are advisory + explicit opt-in with cost surfaced. Like the
[guardrail slice](guardrail-slice.md) it PREPARES the security surface, never writes it. A
routine's work-class mapping is admission data proposed as a reviewable change on the
settings-as-code home, and nothing dispatches autonomously until a human lands it.

**Routine identity.** A routine is addressed by its IDENTITY: the bare `<class-token>` for a
single-posture class, or `<class-token>/<posture-token>` (kebab-case segments) for a
multi-posture class whose catalog leaf defines more than one work-class posture, e.g.
`doc-freshness-sweep/advisory` and `doc-freshness-sweep/docs-change`,
`ci-health-review/advisory` and `ci-health-review/ci-config-change`,
`dependency-update-wave/mechanical` and `dependency-update-wave/changelog-informed` (the
canonical posture tokens live in the catalog leaves). A multi-posture class binds PER-POSTURE
identities, never its bare token. Each posture is a distinct work class and therefore a distinct
identity on a distinct emitting surface. The handler serializes its identity as the envelope's
`signal.routine`, and its platform-attested producer as `signal.producer_identity`, required on
every routine-fired temporal signal.

**Binding-home split by governance sensitivity (the guardrail contract's split).** A routine's
`signal.work_class` is stamped, per
[`${CLAUDE_PLUGIN_ROOT}/reference/trigger-dispatch.md`](${CLAUDE_PLUGIN_ROOT}/reference/trigger-dispatch.md)'s
classification rules, from the PROTECTED identity↔surface association the security binding homes. NOT from the `--routine` argument, the scheduled workflow file, or the emitted `signal.raw_link`,
all of which are CLAIMS an agent-writable job could forge and are never trust anchors. That
association is ADMISSION data: it binds ONLY in the security binding's
`admission.classification.temporal` home
([`schemas/guardrails-security-binding.schema.json`](../schemas/guardrails-security-binding.schema.json)),
on the settings-as-code home outside the agents' blast radius. For reconciled existing bots
exactly as for freshly wired routines. Each entry is keyed by routine identity and carries
`{"class": "C1"–"C5", "source_surface": "<surfaces-map id>", "run_link_prefix": "<prefix>",
"producer_identity": "<platform-attested producer ref>"}`: the class the identity's signals
stamp, the one scheduling surface permitted to emit them, the run permalink namespace ratified
for that surface, a platform run URL prefix (`https://…`) for a `ci-cron` surface, or a durable
`file:` or artifact-store URI prefix for a `local-scheduler` surface (weaker authority. A
developer-machine run record or the org's artifact store), which may be repo-scoped and SHARED
across the repo's schedules rather than disjoint per entry, AND the `producer_identity`, the
platform-attested workflow-file or scheduler-unit reference that pins WHICH schedule fired within
that namespace. **One identity per emitting surface**. No two `classification.temporal` entries
may share a `source_surface`, and **producer identities are unique across entries**, so the
producer the platform attests (through the execution-surface attestation and the signal's raw
link and producer reference) is bound to exactly ONE identity. Admission validates the envelope's `(signal.routine, resolved source surface)` pair
against this table AND that `signal.raw_link` falls under the ratified `run_link_prefix` AND that
the attested `signal.producer_identity` equals the entry's ratified `producer_identity` BEFORE
stamping `signal.work_class`; an absent entry, a `source_surface` that does not equal the attested
surface, a raw link outside the ratified prefix, or a producer identity that does not match is
fail-closed human-gated. A swapped `--routine` selector therefore cannot launder high-risk work as
a benign class. Claiming a different identity resolves to THAT identity's own surface and
producer, which the platform-attested producer will not match (a shared run-link namespace no
longer distinguishes schedules on its own). A repo-local class source would be the precise agent-writable bypass
the trigger contract's classification obligation forbids. The NON-security keys, cadence,
enablement, surface choice, are the ONLY routine data that lands repo-local: they go in the
additive `routines` section of the repo-local autonomy binding under `.claude/autonomy/` (the same
artifact the `triggers` section lives in), NEVER in the security binding, whose schema carries only
the `admission.classification.temporal` entries. Two artifacts, two validators; the security axis
resolves from the security binding always, non-security refinement repo-local, per the guardrail
resolution order.

1. **Discover scheduling surfaces + budget posture**. Interview and inspect which scheduling
   surfaces this org has: CI-cron on the CI-orchestration home, a developer-machine scheduler,
   self-run infrastructure, a vendor-hosted preview scheduler (marked examples, not a closed
   list. Research the live surfaces at setup time, never from this doc; preview schedulers are
   moving targets). Record each surface's transport (`poll`, or `push-lifecycle` where the
   surface renews subscriptions) and its `scheduler_class`, the closed discriminator the
   signal-envelope check branches on: `ci-cron` where the surface issues an https run permalink,
   `local-scheduler` where it does not (a durable `file:`/artifact URI stands in). Per-org
   absence of a surface is a binding outcome, never a blocker; budget posture defaults `free`.
2. **Detect-diff-reconcile existing schedulers and bots**, before wiring anything, read what
   already runs: org schedulers, dependency bots, scheduled scanners, existing cron. A live
   agent-judgment bot (a dependency-update bot, a triage bot) IS an instance of a catalog routine
   class, not a rival mechanism: record it in the binding under its routine identity
   (posture-qualified for a multi-posture class) and its surface, reconcile its cadence, and NEVER
   stand up a second mechanism for the same concern. The
   no-agent-session rule holds through reconciliation, a wholly deterministic scheduled check is
   not a routine and keeps running with no agent session, filing work items through the trigger
   adapters; only its judgment-bearing successor, where one exists, is the routine, and a hybrid
   class (e.g. `dependency-update-wave`) reconciles as its split: detection half judgment-free,
   judgment half the routine. A stale or duplicate bot is surfaced as the diff and reconciled,
   never silently overwritten.
3. **Wire free defaults as reviewable changes**. For each enabled routine on a free surface the
   wiring is reviewable changes across role homes, never one agent-written file:
   - the CI-cron handler shape from
     [`templates/routine-definitions.md`](../templates/routine-definitions.md) lands on the
     CI-orchestration home (the scheduled job that emits the routine's `temporal` signal into the
     queue);
   - the enabling settings, which routine identities are on, at what cadence, on which surface,
     land as the `routines` section of the repo-local autonomy binding under `.claude/autonomy/`
     (the same artifact as the `triggers` section);
   - the protected identity↔surface association, each routine identity →
     `{class, source_surface, run_link_prefix, producer_identity}`, one entry per identity, no two
     sharing a surface and no two sharing a `producer_identity`, lands as the
     `admission.classification.temporal` change PREPARED for the security binding on
     the settings-as-code home (a separate artifact from the autonomy binding above).

   Every shape enqueues through the trigger contract's `temporal` adapter and the one dispatch
   entrypoint; no routine executes work in its own handler and no second scheduling path is
   created.
4. **Advise paid/preview surfaces**, a vendor-hosted or preview scheduler that carries a
   plan/seat cost is advisory + explicit opt-in, cost surfaced first, never the default path. An
   entitlement gap routes the surface to the advisory step; the free CI-cron/local-scheduler floor
   covers the default path with zero paid dependencies.
5. **Record the binding**, the `routines` section of the repo-local autonomy binding under
   `.claude/autonomy/` (additive, absent-section tolerance, no major bump, the SAME artifact and
   shape as the `triggers` section), NON-security keys only. This section NEVER enters the security
   binding; the ratified `admission.classification.temporal` entries are a separate artifact under
   the security schema and checker.

   | Key | Value |
   |---|---|
   | `surfaces` | object keyed by scheduling-surface id, the SAME shape the [trigger slice](../SKILL.md#triggerdispatch-slice)'s `surfaces` map uses (`{"class": "temporal", "transport": "poll"\|"push-lifecycle", "scheduler_class": "ci-cron"\|"local-scheduler", "execution_surface": "<recorded id>"}`; a `local-scheduler` surface using an org artifact store also declares `artifact_schemes`). Record a surface here ONLY when the trigger slice has not already recorded it. [`scripts/check-signal-envelope.mjs`](../scripts/check-signal-envelope.mjs)'s resolver merges every section's `surfaces` map and refuses an id recorded in two sections as ambiguous; a routine riding an already-recorded surface REFERENCES its id, it does not re-declare it |
   | `enabled` | object keyed by the FULL routine identity (`<class-token>` or `<class-token>/<posture-token>`). Each entry `{"source_surface": "<surfaces-map id>", "cadence": "<schedule expression or token>", "enabled": <bool>}`; cadence, enablement, and surface choice ONLY. Its `source_surface` MUST agree with the same identity's `source_surface` in the security binding's `admission.classification.temporal`. Binding review and the envelope checker catch drift. The class, its `run_link_prefix`, and its `producer_identity` are NOT here; an identity with no protected classification entry, or one whose surface disagrees, stays unclassified and fail-closed human-gated |

6. **Conformance**, the wired state is reached when
   [`scripts/check-signal-envelope.mjs`](../scripts/check-signal-envelope.mjs), run with BOTH
   `--binding` at the repo-local autonomy binding (the `routines`/`triggers` surfaces) AND
   `--security-binding` at the security binding (the `admission.classification.temporal` entries),
   confirms `signal.routine` is present, resolves `signal.source_surface` to a recorded surface
   with its temporal raw-link form, and verifies any stamped `signal.work_class` matches the
   protected classification entry for that `(identity, surface)` pair AND that `signal.raw_link`
   falls under that entry's ratified `run_link_prefix` AND that the attested
   `signal.producer_identity` equals that entry's ratified `producer_identity`; a missing
   `signal.routine`, an unresolvable surface, an identity↔surface mismatch, a raw link outside the
   ratified prefix, a `producer_identity` mismatch, or an unclassified class is a finding.
