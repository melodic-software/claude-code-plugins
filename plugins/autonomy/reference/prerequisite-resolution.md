# Routine prerequisite resolution

Normative contract for answering, per repository and per scheduling surface, which routine
identities can run — and why. This document owns vocabulary, grain, probe classes, precedence,
composition seams, and consumer rules. Per-class prerequisite facts live in each `v1` definition
leaf under the single-home rule; they are never duplicated here.

The catalog states what happens when a prerequisite is missing
([Access to prerequisites](routines.md#access-to-prerequisites)): missing surface or entitlement
routes to the advisory path, never a silent degrade. This contract owns the question that
precedes that consequence: which identities resolve as eligible against this repository at all.
Decisions are recorded in
[ADR 0011](../../../docs/adr/0011-resolve-routine-prerequisites-per-identity-declared-over-detected.md).

## Output grain

One resolution per **routine identity** — `<class-token>` or `<class-token>/<posture-token>` —
computed for the pair (identity, its one bound scheduling surface). Class axes (Access class,
isolation floor, per-class prerequisites) are the derivation source; the posture refines them;
the identity is the emission key. A class-level verdict cannot express that an advisory posture
is runnable while its direct-change sibling is not — and every consuming artifact
(`routines.enabled`, prepared admission entries) is already identity-keyed.

Non-repo-file signals are **surface-qualified**: a capability present on one execution surface
says nothing about another. The same per-surface doctrine the setup contract states for isolation
substrates binds here. Isolation bindings key on execution-surface ids; the scheduling
`surfaces` map carries `execution_surface` as a field — the two keyspaces stay distinct.

## Candidate set

- **`v1` rows only.** They alone have definition leaves, and posture tokens are leaf-owned.
- **`join:` rows** report under the join-row marker `deferred-class`. A `join:` row has no leaf
  and therefore no identities to resolve; `deferred-class` is a catalog-row marker, not a
  verdict.
- **`not-a-routine` rows** are outside the domain. No agent session exists to bind, so any
  verdict for them is a category error.

## Verdict vocabulary

Four fail-closed verdicts:

| Verdict | Meaning |
|---|---|
| `supported` | Every required prerequisite for the identity on this surface is established |
| `conditional` | The identity clears only under named conditions stated in provenance (for example, an enablement gate only partly resolvable from committed surfaces) |
| `unsupported` | At least one required prerequisite is established as absent on this surface |
| `unknown` | At least one required prerequisite cannot be established or denied — distinct from `unsupported` |

`unknown` is first-class. Both `unsupported` and `unknown` route to the advisory path the
trigger contract already owns for a missing surface or entitlement. A positive verdict
(`supported` or, where conditions clear, `conditional`) must be **provably reachable**: a
resolver that hardcodes `unknown` would pass every fail-closed test and ship silently.

Two constraints bind the vocabulary by construction:

- No token may read as a security-binding assertion. `binds` already means "has a ratified
  identity entry on the security binding"
  ([Routine identity](routines.md#routine-identity); [binding seam](binding-seam.md)).
- No token may read as health. `ok`, `available`, `healthy`, and `pass` are barred.

## Probe classes

Four classes, named for what they read. Presence-shaped signals are probed by a script with no
agent session. Semantic questions (does the test suite discriminate; which architecture rules
apply; what a prose convention implies) are judgment-only: they resolve to `unknown` with a
named follow-up, or to an interactive proposal pass — never to a file-presence heuristic. The
catalog's `DET` / `AGT` tokens are judgment verdicts carrying "not a routine, zero agent
tokens"; they are not reused as probe labels.

1. **repo-file** — build and dependency manifests, test config, CI config, tracker binding,
   flag-system SDK presence: deterministic glob and manifest probes.
2. **harness-context** — `.mcp.json` server inventory, repo-declared plugins, committed skills:
   deterministic reads of structured, committed surfaces. `.mcp.json` **presence is not
   availability**: enablement is settings-gated (`enableAllProjectMcpServers` /
   `enabledMcpjsonServers` / `disabledMcpjsonServers`), owned by the `claude-config` audit and
   composed presence-gated, never re-implemented here. Servers also arrive from user scope and
   plugins. The probe reports presence and the enablement gate separately.
3. **machine-context** — CLI availability, local substrates: deterministic, per-surface. A
   result is a claim about the probed surface only, never a repo claim.
4. **prose-context inference** — `CLAUDE.md`, `AGENTS.md`, README: judgment-only inference
   source for *proposing* declarations into non-security keys, interactively. The deterministic
   resolver never parses prose, and prose is never runtime authority. Platform bound: Claude
   Code reads `CLAUDE.md`, not `AGENTS.md` — an `AGENTS.md` reaches a session only through a
   reference.

Probe evidence is durable per surface under the existing isolation-binding pattern. Only signals
with no owner (CI-config presence, flag-SDK presence) gain probes owned by this contract;
everything else composes an owning consumer surface below.

### Bounded limitations (stated up front)

- **MCP enablement** is only partly resolvable from committed surfaces
  (`.claude/settings.local.json` and user scope are invisible to a clone). On a scheduled run an
  MCP-dependent identity resolves `conditional` at best, and `unknown` where enablement is
  undeterminable.
- **Personal ecosystem layers** (user-global and `.local.yaml`) are uncommitted. A scheduled
  cloud run resolves identities that depend on them `conditional` at best, and `unknown` where
  undeterminable.

Both are fail-closed working as designed.

## Precedence

A declaration is evidence of intent; a probe is evidence of fact. Precedence is directional —
declared narrows and fills where no contradicting fact exists; intent never outranks a fact.

- **A declaration may narrow or disable.** A declared-absent or disabled surface is out of
  consideration whatever a probe finds. Detection fills gaps and proposes declarations; it never
  silently overrides one.
- **A probe that ran and returned negative caps every declaration.** Where a tracked declaration
  asserts a prerequisite and the current per-surface probe shows it missing, the identity
  resolves to `unsupported`. A positive verdict never survives the capability's disappearance on
  evidence of intent alone. The contradiction is simultaneously emitted as a **finding** and
  routed per the
  [liveness-assertion](../../../docs/conventions/liveness-assertion/README.md) Core contract's
  two limbs (fail loud, or publish to a channel an agent reads): in a gate context the
  resolver's non-zero exit is the loud limb; in a report context the divergence finding in the
  emitted resolution is the agent-readable one; the interactive `apply` path additionally
  proposes correcting the declaration.
- **A probe that could not run is not a probe that returned negative.** The two states never
  collapse. Where no probe can execute — an uncommitted layer on a scheduled run, or a surface
  whose probe can confirm but not deny — the declaration stands and the verdict is qualified
  (`conditional` or `unknown` as the signals warrant), with the unprobeable state named in
  provenance.

Proposing is **interactive-only**. Non-interactive and forked contexts are barred from
ask-and-persist rungs, so at routine runtime the resolution reports and never persists.

### Per-rung ownership

Connector entitlement for `prod` / `product` / `org` / `ext` binds at the **org rung** of the
binding seam. A lower rung never asserts a prerequisite a higher rung owns. Security axes accept
no repo-local value at all (this plugin's ratified cascade deviation).

## Composition seams

Resolution composes convention-owned consumer surfaces. Every cross-plugin reference is
presence-gated with a documented fallback per
[seam phrasing](../../../docs/conventions/seam-phrasing/README.md):

| Concern | Seam | Fallback when absent |
|---|---|---|
| Ecosystems | Toolchain seam (when the `toolchain` plugin is installed), reading *resolved* consumer state under `.claude/ecosystems/<eco>.yaml` — an ecosystem present but `enabled: false` is not configured; uncommitted user-global and `.local.yaml` layers report unresolvable | Inference from the repo's own build files; never another plugin's bundled defaults |
| MCP enablement | `claude-config` audit surface (when the `claude-config` plugin is installed) | Report `.mcp.json` presence only; name enablement as unprobeable in provenance |
| Tracker | Work-item tracker seam — `.work-item-tracker.json` plus the bound adapter's `capabilities.json` (when the `work-items` plugin is installed) | Treat tracker-dependent prerequisites as unestablished (`unknown`) |
| Substrates, schedulers, observability | Autonomy setup skill's own discovery slices | Same plugin — no gate |
| Configured-surface enumeration | Each surface's own presence in the repo | Never by reading the config-cascade registry table (a conformance ledger, not a runtime inventory) |
| Ownerless signals (CI-config presence, flag-SDK presence) | Probes owned by this contract | N/A |

Absence of a composed seam is a verdict input, not an error.

## Consumers — narrows an existing enforcement input and adds none

The resolution is never admission data. Its two consumers are:

1. An input to the human-landed *prepared* change to the settings-as-code security binding — the
   setup slice prepares, never writes, that surface.
2. A **narrowing-only** influence on the repo-local `routines.enabled` section, which existing
   envelope conformance already validates claims against. An identity may be enabled only when
   its verdict clears; an identity with no protected classification entry stays unclassified and
   fail-closed human-gated regardless.

A repo-local input to a protected path would be the precise agent-writable bypass the
classification obligation forbids.

## Configured is not working

Presence establishes configured, never health. The verdict vocabulary is non-health-asserting by
construction. The
[liveness-assertion](../../../docs/conventions/liveness-assertion/README.md) on-touch obligation
still binds every implementing engine surface (the setup `check`, the resolver): each states its
taxonomy row and how it satisfies fail-loud or agent-readable routing. A consumer that treats
configured as working is itself the false-green defect. Execution evidence belongs to the
consuming routine.

## Recompute; committed surfaces for scheduled runs

The resolution recomputes at every consumption — a setup `check`, a pre-enablement gate, an
advisory read. A persisted verdict is never authority. The only persisted artifacts are
human-ratified declarations (an additive section of `.claude/autonomy/binding.json` that
references existing scheduling-surface ids and declares no `surfaces` map of its own, keeping
envelope conformance unambiguous) and surface-qualified probe evidence under the existing
isolation-binding pattern.

Scheduled runs read **committed surfaces only**. A cloud run clones from the default branch; a
capability claim sourced from one operator's machine is false in every other execution context.

## Landing and implementation boundary

This contract lands as one document under `reference/` per the
[binding-seam layout rule](binding-seam.md#layout-convention). Implementation phases extend the
autonomy setup skill as a slice: per-class facts in `v1` leaves, a generated drift-gated
machine-readable emission derived from those leaves (leaves stay the authored home; the resolver
reads structure, never prose), the deterministic resolver, and the setup slice. No new plugin,
no new skill, no new catalog, no new config-file family.

## Disambiguation — five incumbents this term is not

**Routine prerequisite resolution** uses the catalog's own noun for these facts. It is not:

1. **Guard-plugin "capability detection"** — session-auth, fail-open, session-scoped
   (`plugins/rate-limit-guard/reference/reader-contract.md` §Capability detection (fail-open);
   mirrored in `context-guard`; consumed by work-loop, babysit-loop, attend-queue). Fail-open is
   that posture; this contract is fail-closed.
2. **Autonomy's internal "capability"** — a shipped contract area
   ([binding seam](binding-seam.md#layout-convention): "Each capability … lands exactly one
   contract document"; setup skill "capability slices").
3. **Verification-topology model-capability labels** — rejected vocabulary.
4. **Loop-lane capability tiers** — model selection (`docs/conventions/loop-lane/`).
5. **Tracker adapter `capabilities.json`** — declared adapter verb support; a composed input
   here, not a synonym.

The catalog's `DET` / `AGT` judgment verdicts are a sixth nearby collision (not probe labels);
they are called out under Probe classes above rather than as a sixth "capability" sense.
