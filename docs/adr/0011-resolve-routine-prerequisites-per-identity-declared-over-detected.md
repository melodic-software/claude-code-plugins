# Resolve routine prerequisites per identity and surface, declared over detected

- Status: accepted
- Date: 2026-08-15

## Context

The routine catalog states what happens when a prerequisite is missing — "routes to the advisory
path … never a silent degrade" — but no contract, skill, or script answers the question that
precedes it: *which routine identities can run against this repository at all*. The nearest
incumbents are the autonomy setup skill's per-slice discovery prose and the catalog's
prerequisite-consequence rule, neither a resolution procedure. Meanwhile nearly every input
surface already has an owner: the toolchain resolution ladder owns ecosystem inference, the
work-item tracker seam owns tracker binding, the `claude-config` audit owns MCP-enablement
conformance, and the setup skill's slices own substrates, schedulers, and observability.

Fleet ladders (toolchain: config present → infer, then offer to persist → ask → default) and the
external consensus verified at primary sources (Renovate onboarding, Linguist overrides,
buildpacks' declared detect order, Dependabot's declared-only model) agree on one shape:
detect → propose → human ratifies → declaration governs, recomputed per run, with no cached
capability profile as truth.

Naming is constrained by five incumbents: "capability detection" is the guard plugins'
session-auth term with the opposite (fail-open) default; "capability" alone already means a
shipped contract area inside the autonomy plugin itself; verification-topology rejects
model-capability labels; loop-lane owns capability *tiers* (model selection); and the tracker
adapter's `capabilities.json` declares adapter verb support. The provisional term is therefore
**routine prerequisite resolution** — "prerequisite" is the catalog's own noun for these facts —
with the final ruling on tokens and the artifact name kept human (below).

This decision was planned in the `routine-capability-detection` topic slice (promoted from the
boris-routines-adoption plan's Phase 8 by #2685; parent contract carried by PR #2686). The
interview's 16 branches were answered and adversarially validated by fresh-context agents with
rationale withheld, then the plan took independent adversarial and conformance passes; the slice
is pruned per the contract-slice lifecycle, and the durable record is this ADR plus the filed
implementation issues.

## Decision 1 — the grain is the routine identity on its surface, never the repo

One resolution per routine identity (`<class-token>` or `<class-token>/<posture-token>`), computed
for the pair (identity, its one bound scheduling surface). Class axes are the derivation source;
the posture refines it; the identity is the emission key. A class-level verdict cannot express
that an advisory posture is runnable while its direct-change sibling is not — and every consuming
artifact (`routines.enabled`, prepared admission entries) is already identity-keyed. Non-repo-file
signals are surface-qualified: a capability present on one execution surface says nothing about
another, the same per-surface doctrine the setup contract states for isolation substrates.

Candidate set: `v1` rows only. A `join:` row has no leaf and therefore no identities — it reports
under a deferred-class marker, not a verdict. A `not-a-routine` row is outside the domain; a
verdict for it is a category error.

Verdicts are fail-closed, `unknown` first-class and distinct from the negative verdict, and a
positive verdict must be provably reachable (a resolver hardcoding `unknown` would otherwise pass
every fail-closed test and ship silently). Two constraints bind whatever token names are ruled:
no token may read as a security-binding assertion (`binds` already means "has a ratified identity
entry on the security binding"), and no token may read as health — the vocabulary is
non-health-asserting by construction; the liveness-assertion contract's on-touch obligation still
binds every implementing engine surface, which states its taxonomy row and fail-loud behavior
rather than claiming exemption. A consumer that treats *configured* as *working* is itself the
false-green defect.

## Decision 2 — declared narrows and fills; a ran-and-negative probe caps every declaration

A declaration is evidence of intent; a probe is evidence of fact. The precedence is directional,
never flat — the title's "declared over detected" names the default (intent narrows and fills
where no contradicting fact exists); it never licenses intent to outrank a fact. Normatively:

- **A declaration may narrow or disable.** A declared-absent or disabled surface is out of
  consideration whatever a probe finds; detection fills gaps and proposes declarations, never
  silently overrides one.
- **A probe that ran and returned negative caps every declaration.** Where a tracked declaration
  asserts a prerequisite and the current per-surface probe shows it missing — a required CLI
  removed, an entitlement revoked, an MCP server gone — the identity resolves to the negative
  verdict: a positive verdict never survives the capability's disappearance on evidence of
  intent alone. That would be the healthy-while-dead class the liveness-assertion Core contract
  exists to prevent. The contradiction is simultaneously emitted as a **finding** — someone's
  tracked configuration is now wrong, and the moment of detection is the one moment the drift is
  visible — routed per that contract's two limbs (fail loud, or publish to a channel an agent
  reads; `docs/conventions/liveness-assertion/README.md` owns the definitions): in a gate
  context the resolver's non-zero exit is the loud limb; in a report context the divergence
  finding in the emitted resolution is the agent-readable one; the interactive `apply` path
  additionally proposes correcting the declaration.
- **A probe that could not run is not a probe that returned negative.** The two states never
  collapse. Where no probe can execute — an uncommitted layer on a scheduled run, or a surface
  whose probe can confirm but not deny (relocatable CI configuration is the canonical case) —
  the declaration stands and the verdict is qualified, with the unprobeable state named in
  provenance.

Proposing is interactive-only — non-interactive and forked contexts are barred from
ask-and-persist rungs, so at routine runtime the resolution reports and never persists. Per-rung
ownership is part of the contract: connector entitlement for `prod`/`product`/`org`/`ext` binds
at the org rung, a lower rung never asserts a prerequisite a higher rung owns, and security axes
accept no repo-local value at all. Prose (CLAUDE.md, AGENTS.md, README) is an inference source
for proposals into non-security keys, never runtime authority, and is never parsed by the
deterministic resolver.

Two flat rules were rejected. "Declared wins, always" lets a stale positive declaration keep a
routine admitted after the capability disappeared — fail-open through the back door. "Detected
wins, always" would silently rewrite human-ratified intent and erase deliberate narrowing;
staleness is handled by divergence findings, not by either inversion.

## Decision 3 — compose the owning consumer surfaces; no new prober, no cached profile

Resolution composes convention-owned consumer surfaces, each cross-plugin reference
presence-gated with a documented fallback: the toolchain seam for ecosystems (reading *resolved*
state — an ecosystem present but disabled is not configured; fallback is inference from the
repo's own build files, never another plugin's bundled defaults), the `claude-config` surface for
MCP-enablement conformance, the tracker seam plus the bound adapter's `capabilities.json`, and
the autonomy setup skill's own discovery slices. Configured surfaces are enumerated by their own
presence in the repo, never by reading the config-cascade registry table (a conformance ledger,
not a runtime inventory). Only signals with no owner (CI-config presence, flag-SDK presence)
gain probes owned by the new contract.

Two limitations are stated up front rather than discovered later: scheduled runs read committed
surfaces only, and both MCP enablement and the personal ecosystem layers are only partly
committed — so on a cloud run an identity depending on them resolves conditionally at best, and
`unknown` where undeterminable. That is fail-closed working as designed.

The resolution recomputes at every consumption; a persisted verdict is never authority. The only
persisted artifacts are human-ratified declarations (an additive section of
`.claude/autonomy/binding.json` that references existing scheduling-surface ids and declares no
`surfaces` map of its own, keeping envelope conformance unambiguous) and surface-qualified probe
evidence under the existing isolation-binding pattern.

It lands as one contract document in `plugins/autonomy/reference/` with per-class facts in each
`v1` leaf (single-home rule). Between the authored leaves and the resolver sits one **generated,
drift-gated machine-readable emission** derived from the leaves — the generate-plus-check pattern
the catalog generator established — so the leaves stay the single authored home and the resolver
reads structure, never prose. The emission is generated in-plugin output, not consumer
configuration. Implementation extends the setup skill as a slice. No new plugin, no new skill, no
new catalog, no new config-file family.

## Decision 4 — the resolution narrows an existing enforcement input and adds none

It is never admission data. Its two consumers are: an input to the human-landed *prepared* change
to the settings-as-code security binding (the slice prepares, never writes that surface), and a
narrowing-only influence on the repo-local `routines.enabled` section, which existing envelope
conformance already validates claims against. An identity with no protected classification entry
stays unclassified and fail-closed human-gated regardless. A repo-local input to a protected path
would be the precise agent-writable bypass the classification obligation forbids.

## Consequences

- A repository operator — or an unattended run — can ask "which routine identities can run here,
  and why" and get per-identity verdicts with per-signal provenance, instead of re-deriving
  eligibility ad hoc per routine.
- Detection can never widen autonomy: declarations are human-ratified, enablement is
  narrowing-only, admission stays fail-closed on its own inputs. The cost is accepted friction —
  a genuinely capable repo still needs a human to ratify what detection proposes.
- A stale **positive** declaration cannot sustain a positive verdict: a ran-and-negative probe
  caps it, and the contradiction surfaces as a finding at the first recompute. A stale
  **narrowing** declaration (a disabled surface that has since reappeared) persists until a
  human acts on its divergence finding — narrowing staleness costs availability, never safety.
- The generated emission adds a drift gate to CI; the leaves remain the only authored home for
  per-class facts.
- Final naming is deliberately not settled here: the verdict tokens, the deferred-class marker,
  and the contract noun/artifact filename take one human ruling, tracked as the blocking gate on
  the contract-document issue.
- Implementation is sequenced in five issues (contract doc — blocked on the naming ruling;
  per-identity prerequisite sections in the ten `v1` leaves; the generated emission with its
  drift gate; the deterministic resolver; the setup slice), each carrying its own version bump,
  CHANGELOG entry, and inlined incumbent evidence.

## Amendment (2026-08-16) — the naming ruling, and its reconciliation with the shipped state

The human naming ruling this ADR deferred to landed on #2717 — after the contract document and
its downstream phases had already merged with a working vocabulary. The ruling's premise ("the
contract document may be authored against these") was stale when written; this amendment is the
reconciliation of record.

- **Verdict tokens: the shipped set is ratified.** `supported` / `conditional` / `unsupported` /
  `unknown` stays. The ruling's `met` family was a precision preference, not a defect cure: the
  shipped set clears every constraint that binds — no security-binding reading, no barred health
  word, no collision with the five named incumbents. Migrating ~60 sites across four merged PRs,
  including machine-emitted resolver tokens, buys no correctness.
- **The deferred marker gains its mandatory trigger: `deferred(<trigger>)`.** This half of the
  ruling names a genuine defect: a bare marker records that resolution is postponed while
  discarding the condition under which the deferral is revisited — the half that makes it
  auditable rather than an indefinite hold. The trigger is the `join:` row's own catalog Status
  trigger; the parameterized shape reuses the deferral-with-explicit-trigger idiom already in
  `work-classes.md`.
- The contract noun and filename were confirmed unchanged.
