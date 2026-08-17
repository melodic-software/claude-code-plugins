# Coupling assessment model

How to judge whether two things are coupled, how badly, and whether it matters. Read this before
scanning; the scan's job is to emit findings typed against this model, not ad-hoc impressions.

## Contents

- What counts as coupling — the change-centric definition and the edge form
- The strength ladder (structured design) — content through message coupling
- Connascence — static and dynamic forms; the strength, degree, and locality axes
- Volatility weighting — co-change evidence, blast radius, the ranking formula
- Altitudes — the same model at code, module, application, repository, and document scale
- What is NOT a finding — the carve-outs that keep the scan honest

## What counts as coupling

Two artifacts are coupled when a change to one forces, or silently invalidates, the other. The
artifacts can be functions, types, modules, layers, applications, repositories, documents, or
config. The definition is change-centric on purpose: coupling that never transmits change is
latent, not live, and ranks below coupling on a hot path of change.

Coupling is a pairwise property with a direction. Record every finding as
`A --(kind, via)--> B`: what depends on what, through which mechanism (import, shared type, shared
mutable state, string contract, file path, copied text, deploy ordering, timing).

Cohesion is the dual, not a separate topic: grouping what changes together *is* the removal of
coupling across the group boundary. Low cohesion inside a unit shows up as high coupling around
it. The steering rule is Constantine's: maximize cohesion within a boundary, minimize coupling
across it.

## The strength ladder (structured design)

Ordered worst to best. When classifying, pick the highest rung that applies — a pair can be
coupled several ways at once.

1. **Content coupling** — one unit reaches into another's internals: private state, internal
   file layout, another module's non-published members, another repo's internal paths.
2. **Common coupling** — units share mutable global state: a global variable, a singleton
   holder, a shared config object anyone mutates, a database table two applications both write.
3. **External coupling** — units share an externally imposed format, protocol, or device
   knowledge that neither owns, duplicated in each.
4. **Control coupling** — one unit passes a flag that selects the other's behavior: boolean
   parameters, mode enums switched on inside, "type code" dispatch.
5. **Stamp coupling** — a unit receives a composite structure but uses a fragment of it,
   binding it to the whole structure's shape anyway.
6. **Data coupling** — units share only the primitive data they need. Benign; the baseline.
7. **Message coupling** — units interact only through messages/events with no knowledge of each
   other's identity. Loosest form that still communicates.

## Connascence — the finer instrument

Two elements are connascent when a change in one requires a coordinated change in the other.
Use it to compare findings that sit on the same ladder rung.

Static forms, weakest to strongest: **name** (must agree on a name), **type**, **meaning**
(magic values interpreted identically — `-1` means missing, `"admin"` means privileged),
**position** (argument order, column order), **algorithm** (two sides must implement the same
algorithm — hashing, serialization, validation duplicated across a boundary).

Dynamic forms, all stronger than static: **execution order** (A must run before B),
**timing** (timeouts, sleeps, race-sensitive ordering), **value** (several values must change
together to stay consistent), **identity** (two units must reference the very same instance).

Three axes score any instance:

- **Strength** — how hard the coordinated change is to make and to detect when missed.
- **Degree** — how many sites participate. Connascence of name across 3 call sites is nothing;
  across 200 sites it is a migration project.
- **Locality** — how far apart the connascent elements sit. Strong connascence inside one
  function is fine; the same connascence across a repo boundary is a defect.

The management rules: convert stronger forms to weaker ones (connascence of position → name;
meaning → a named constant or type; algorithm → one shared implementation), reduce degree, and
keep whatever strength remains as local as possible. "Keep strong connascence local" is why a
finding's rank must include distance, not just kind.

## Volatility weighting — coupling only costs where change happens

A dependency on something stable is cheap regardless of kind; the standard library is maximal
coupling nobody minds. Weight every finding by:

- **Volatility of the depended-on side** — how often does it actually change? Version-control
  history is evidence; kind of artifact is a prior (third-party APIs, config formats, and UI
  copy are volatile; core domain vocabulary is not).
- **Co-change evidence** — files or repos that repeatedly change in the same commits/PRs
  without a declared dependency are coupled through a channel the dependency graph cannot see
  (shared assumption, copied logic, implicit contract). Mine the log for pairs with high
  co-change frequency; these outrank most statically visible findings.
- **Blast radius** — afferent coupling (how many depend on it). Instability `I = Ce / (Ca + Ce)`
  gives the orientation rule: depend in the direction of stability; things many depend on
  should be abstract and stable, things that change freely should have few dependents.

Rank order for the ledger: `strength × degree × distance × volatility`. A weak-but-everywhere
coupling on a hot path outranks a strong-but-local one in dead code.

## Altitudes

The same model applies at every altitude; only the mechanisms differ.

- **Within a code unit** — feature envy, temporary fields, reach-through chains (Law of
  Demeter), boolean control parameters.
- **Between modules/layers** — imports of internals instead of published surface, dependency
  direction violations (domain → infrastructure), shared internal types across module
  boundaries, framework types leaking into domain code.
- **Between applications/services** — shared databases (common coupling at system scale),
  synchronous call chains (temporal coupling: both must be up simultaneously), duplicated
  validation or serialization logic (connascence of algorithm), implicit string/JSON contracts
  with no owned schema, deploy-order requirements (connascence of execution order).
- **Between repositories** — one repo hardcoding another's file paths, branch names, or
  internal layout; copied code or prose that must track its source; version pinning against
  another repo's unversioned internals instead of a released contract.
- **Between documents** — the same fact stated in N places (connascence of value in prose);
  deep links into another document's private structure instead of its stable entry point;
  hardcoded `file:line` references; counts and inventories restated where they can be derived.
  A doc that must be edited whenever code changes, without any check forcing it, is the silent
  form: it does not break, it rots.

## What is NOT a finding

- A dependency on a stable, owned, in-process abstraction. Dependency count is not coupling
  badness; direction, strength, and volatility are.
- Deliberate, declared coupling at a published seam — an explicit contract, a versioned API, a
  documented extension point. The seam is the fix working, not the disease.
- Layered propagation of one change (entity + DTO + mapper + migration for a new field) —
  necessary plumbing, not shotgun surgery. Shotgun surgery is duplicated *logic*, not required
  per-layer representation.
- Framework-imposed conventions inside the framework's own zone (an ORM entity referencing ORM
  types in the infrastructure layer).
