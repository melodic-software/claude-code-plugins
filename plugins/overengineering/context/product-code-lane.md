# Product-code lane — the lane binding

The second lane of this plugin's scrutiny method, covering code-level overengineering in product
code: speculative abstraction, unearned indirection, premature generality.

**The method is not restated here.** [`scrutiny-method.md`](scrutiny-method.md) §§1-12 are
lane-independent and apply verbatim. This document supplies only the four things its "Lane binding"
section asks a lane for: the item inventory, the layer vocabulary and discovery probes, the evidence
sources mapped onto the §2 tiers, and the lane's protected-class defaults extending §7. Every bare
`§N` below is a section of that document.

Status: **specification**. The lane's shipping shape is recorded in
[ADR 0017](../../../docs/adr/0017-ship-the-product-code-lane-as-its-own-skill.md); this document is
what that skill binds when it lands.

## Why this lane needs its own binding at all

The enforcement lane audits mechanisms that *govern* work. This lane audits the code that *does* the
work, and the difference changes what evidence exists, what a retirement costs, and what may not be
touched:

- Retiring an enforcement mechanism removes a check. Retiring an abstraction **changes code that
  runs**, so §11's rollback ladder carries behavior risk the enforcement lane does not.
- Enforcement mechanisms are sparse and individually named. Product code is dense, so §1's carry
  cost is paid per *reader*, and the item inventory below has to aggregate or it will produce a wall
  of findings rather than a spine.
- Fowler's YAGNI is *about* product code, which makes §10's boundary load-bearing here rather than a
  corner case. Restated for this lane below.

## 1. Item inventory — what counts as one auditable artifact

**The item is the abstraction, never the file.** One item is a construct plus everything that exists
to serve it: the declaration, its implementations, its registration or wiring, and its call sites. An
interface with three implementations and eleven call sites is **one** item with a members list, not
fifteen findings.

This is the enforcement lane's aggregating-container rule
([`../skills/audit/context/surface-walk.md`](../skills/audit/context/surface-walk.md),
"Granularity") applied to code. Two consequences worth stating because they are easy to get wrong:

- A file touched by several unrelated items is not itself an item. Attribute each finding to its
  abstraction and let the file appear in several members lists.
- A single-member container is still a container. An interface with exactly one implementation is the
  canonical finding of this lane, and reporting it as "one interface" rather than "an interface and
  its sole implementation" hides the cost being argued about.

## 2. Layer vocabulary and discovery probes

Eight layers, each a distinct *shape* of unearned generality. They are ordered by how cheaply the
evidence usually settles them, so a scoped pass can stop early.

The probes below are deliberately written as starting points, not as a portable command set. This
plugin's consumers span languages with incompatible tooling, and a grep that is precise in one
ecosystem is noise in another. Resolve each probe against the consumer's actual language and
toolchain, and record which probe form was used, per §2's rule that a verdict names the source it
consulted.

### Layer 1 - `single-implementation` (unearned indirection)

Interfaces, abstract bases, protocols, and traits with exactly one concrete implementation; wrapper
types whose every method delegates without adding behavior.

**Discovery probes.** Enumerate declared abstract types, then count concrete implementors of each.
The count is the finding; the history is the verdict.

**Layer notes.** A single implementation is a *question*, never a verdict on its own. Test doubles,
declared external implementors, and dependency-inversion boundaries that exist to break a compile-time
cycle are all legitimate single-implementation cases. §4's intent reconstruction is what separates
them.

### Layer 2 - `extension-points`

Registries, strategy tables, factory maps, plugin loaders, and hook dispatchers with zero or one
registered member.

**Discovery probes.** Find the registration surface, then enumerate registrations. An extension point
whose only registration is its own default is the shape this layer exists to surface.

### Layer 3 - `configuration`

Options, settings, feature flags, and tunables whose non-default value is never set anywhere in the
tree, in deployment configuration, or in recorded runtime.

**Discovery probes.** Enumerate declared options, then search for each being *set* rather than *read*.
An option only ever read is a constant with extra steps.

**Layer notes.** Overlaps the enforcement lane where the option gates a mechanism. Attribute to
whichever lane owns the thing being configured, and cross-reference rather than reporting twice.

### Layer 4 - `generality` (premature parameterization)

Type parameters, generic containers, and function parameters instantiated at exactly one type or
called with exactly one value at every call site.

**Discovery probes.** For each parameter, collect the set of distinct arguments across all call sites.
A set of size one is the finding.

### Layer 5 - `layering` (pass-through)

Layers that only forward: mappers between shapes that are structurally identical, repository or
service wrappers that add no behavior over what they wrap, DTOs identical to the entity they mirror.

**Discovery probes.** For each layer boundary, sample the transformations and classify each as
identity or not. A boundary that is all-identity is the finding.

**Layer notes.** The strongest counter-evidence here is a *declared* intent to vary the two sides
independently. §4 asks whether that variation ever arrived; tier 2 answers it.

### Layer 6 - `speculative-api`

Exported or public surface with no in-repo caller and no declared external consumer.

**Discovery probes.** Diff the exported set against the called set. Then check the published-surface
question before drawing any conclusion, because this layer is where the protected classes below bite
hardest: an unused export on a published package is a semver commitment, not dead code.

### Layer 7 - `dead-branches`

Permanently-settled feature flags, unreachable conditionals, and compatibility shims for versions,
platforms, or dependencies no longer supported.

**Discovery probes.** For flags, the tier-1 evaluation record if one exists, else the set of values
the flag is ever assigned. For shims, the declared minimum supported version against the version the
shim targets.

### Layer 8 - `premature-async` (unearned machinery)

Concurrency, caching, pooling, batching, and retry machinery introduced without a measured bottleneck
behind it.

**Discovery probes.** Locate the machinery, then look for the measurement that motivated it: a
benchmark, a profile, a load test, an incident. This layer is where §2's "silence is UNPROVEN, never
KEEP" does the most work, and also where an ablation (§8) is most often unsafe, since removing a
concurrency control can corrupt rather than merely slow.

## 3. Evidence sources, mapped onto the §2 tiers

| Tier | This lane's sources | Lane-specific caveat |
|---|---|---|
| 1 | Coverage records, profiler and APM traces, feature-flag evaluation records, production logs | Coverage is this lane's workhorse tier 1, and its caveat is sharp: coverage records what the **test suite** executed, which is evidence about the suite unless production telemetry corroborates it |
| 2 | The commit that introduced the construct and its linked issue; implementation count over time; churn on the abstraction versus on what it wraps; revert history | The lane's signature probe lives here, see below |
| 3 | Incidents the construct was introduced to prevent, and incidents it caused | Absence stays ambiguous by construction (§7) |
| 4 | Author or maintainer attestation: the consumer that was planned, the variation that was expected | Recorded as attestation with date and speaker, never promoted to a measurement (§2) |
| 5 | Docstrings claiming extensibility, ADRs, design docs, TODO and FIXME notes | Claims to verify, nothing more; a docstring promising extensibility is the hypothesis, not the finding |

### The signature probe: did the second implementation ever arrive?

Speculative generality is a **prediction** that variation would arrive. Tier 2 can check the
prediction directly and cheaply, which is what makes this lane tractable at all:

Date the abstraction's introduction, then count its implementations, registrations, or distinct
instantiations at that date and at every point since. A construct built for variation that has stood
at one member for years has a falsified prediction behind it, and that is a tier-2 measurement rather
than a reviewer's taste. A construct that reached two members in a month has an earned keep, on the
same evidence.

State the elapsed time in the finding. "One implementation" is a count; "one implementation across
four years and 200 commits to the file it wraps" is an argument. §9's analogical thresholds govern
how far such a number transfers.

**A shallow clone makes this probe unavailable, not silent** (§2). The preflight below establishes
which it is before any layer runs.

## 4. Protected-class defaults, extending §7

§7's enforcement classes continue to apply where product code implements them, an authorization check
written as a plain function is protected by §7 without needing a second listing. This lane adds
classes whose hazard is specific to changing code that runs:

- **Published API surface with external consumers.** Anything under a semver or compatibility
  commitment. Unused-in-repo is not unused, and this lane's layer 6 will surface these routinely.
- **Serialization, persistence, and wire formats.** Any construct whose shape is written by one
  version and read by another, including database schemas, message payloads, cached representations,
  and on-disk state. Collapsing an "identical" mapper couples the stored shape to the in-memory one.
- **Concurrency and locking primitives.** Removing machinery whose absence corrupts rather than slows.
  Overlaps layer 8 deliberately: that layer finds them, this class caps the recommendation.
- **Error-handling, retry, and timeout boundaries.** A pass-through-looking wrapper is often the only
  place a failure mode is contained.
- **Seams the test suite depends on structurally.** §10's corollary applied to code: an interface
  whose sole non-test implementor is production code, with a test double as its second implementor,
  is a testability seam. Retiring it weakens the practice whose output this lane reads as tier-1
  evidence.

The intentionally-dormant class (§7) carries directly: a compatibility shim with a declared removal
date, and a feature flag mid-rollout, are dormant by design and are not findings.

## 5. Preflight, and what differs from the enforcement lane

The enforcement lane's preflight ([`../skills/audit/context/surface-walk.md`](../skills/audit/context/surface-walk.md),
"Preflight") applies as written: repository presence, shallow-clone detection, history depth,
telemetry sink, incident corpus, custody. Three additions are specific to this lane:

| Probe | What it establishes |
|---|---|
| Language and toolchain inventory | Which discovery probes above are even expressible; a layer with no usable probe in this consumer is reported unavailable, never silently skipped |
| Coverage availability and freshness | Whether tier 1 exists at all, and as of when. A stale coverage artifact is a tier-5 claim about tier-1 data, not tier-1 data |
| Published-surface declaration | Whether this tree publishes a package, library, or API. Settles layer 6's protected-class question before layer 6 runs, rather than per finding |

Generated, vendored, and machine-owned code is **out of inventory**, not audited and reported. It has
an upstream owner, so §12's delegation applies before any verdict is formed.

## 6. Boundary against existing owners

This lane integrates with three neighbours rather than duplicating them. The distinguishing axis is
**retrospective and evidence-gated** versus **prospective and judgment-gated**: this lane is the only
one that asks whether a construct should exist *at all* given what the record says it was built for,
and every verdict it issues cites an evidence tier or is UNPROVEN (§2).

| Owner | Unit of work | Trigger | Question it answers |
|---|---|---|---|
| `/simplify` | the current diff | before merge | Can the code just written be cleaner? |
| `code-tidying:tidy` | a file or region | on demand, mechanical | Can this be restructured safely without changing behavior? |
| `architecture:improve` | a module | forward-looking | What is the better interface for this? |
| **this lane** | an abstraction | retrospective, evidence-first | Has this construct's generality earned its carry cost? |

Three handoffs make the boundary operational rather than declarative:

- **A finding whose answer is "keep, but reshape" is not this lane's.** This lane's remediation
  vocabulary is §11's ladder, retire, collapse, inline, narrow. When the evidence supports keeping the
  seam but the shape is wrong, say so in the finding and hand off to `architecture:improve`, which
  owns redesign and its Design-It-Twice pass.
- **A finding that is safe, mechanical, and behavior-preserving is `code-tidying`'s**, even when this
  lane surfaced it. This lane argues about existence; tidying executes structure-preserving changes.
- **This lane never runs on a diff.** A construct introduced in the diff under review has no tier-2
  history yet, so this lane has nothing to weigh it with. Pre-merge scrutiny of new abstraction is
  `/simplify`'s and review's; this lane needs the record that only time produces.

## 7. The §10 boundary, restated for product code

§10's in-scope/out-of-scope split is where this lane is most likely to be misread, because "delete
the abstraction" and "delete the safety net" can look alike in a diff:

- **In scope.** Generality carried on anticipated need: indirection with one implementor, extension
  points with no extensions, parameters with one argument, layers that only forward, machinery with
  no measurement behind it.
- **Out of scope.** The practices that make change safe, in their code-level form: tests and the
  seams that make code testable, type declarations and the checker that reads them, error handling,
  and the abstractions that exist to contain a failure mode rather than to anticipate a feature.

A finding that reads "remove this interface so the tests can no longer substitute it" is outside this
method, and the correct response is to say so rather than to argue it on carry cost.
