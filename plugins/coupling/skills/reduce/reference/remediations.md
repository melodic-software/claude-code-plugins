# Remediation catalog

Mechanism per finding kind, each with its counterweight. Decoupling has its own failure mode:
indirection added where no change pressure exists. Every entry therefore states when NOT to
apply it. An abstraction earns its place at a volatile or substitutable boundary; wrapping a
stable dependency in an interface is not decoupling, it is a second thing to maintain that
moves in lockstep with the first — the coupling remains, plus a layer.

## Code and module altitude

- **Inject the dependency (DI / Hollywood Principle)** — for hard-wired construction of a
  volatile collaborator, service-locator pulls, singletons smuggling state. Constructor
  injection first; let the composition root own wiring.
  *Not when:* the dependency is a stable value object or pure function — injecting those is
  ceremony.
- **Extract an owned interface at the volatile boundary** — for direct references to
  third-party libraries, infrastructure, transport, or anything with a realistic second
  implementation (including a test double that genuinely needs to differ from the real thing).
  The interface belongs to the consumer's side and speaks the consumer's vocabulary
  (ports-and-adapters), not a mirror of the vendor API.
  *Not when:* one implementation, in-process, stable, and tests run fine against the real
  instance. An interface with a single implementation and an identical surface is needless
  indirection, not loose coupling.
- **Replace control coupling with separate operations or polymorphism** — a boolean/mode
  parameter switched on inside becomes two methods, a strategy, or a lookup; a type-code switch
  duplicated across sites becomes polymorphic dispatch or a registration table.
  *Not when:* the switch exists once, is closed by construction (exhaustive over a sealed set),
  and reads clearly — one honest switch beats a class-per-case explosion.
- **Weaken the connascence** — positional arguments → named/keyword or a parameter object;
  magic values → named constants or types; duplicated algorithms (validation, serialization,
  hashing) → one shared implementation both sides call; implicit ordering → an API that makes
  the order unrepresentable (builder that only yields a valid object, state machine types).
- **Move behavior to the data it envies** — feature envy and reach-through chains resolve by
  relocating the calculation onto the type that owns the state, or by asking the collaborator
  ("tell, don't ask") instead of interrogating its graph.
- **De-globalize shared mutable state** — common coupling via statics/singletons becomes an
  injected instance whose lifetime the composition root owns; shared config objects become
  read-only snapshots handed in.
- **Facade / anti-corruption layer over a messy or foreign surface** — when many call sites
  each reach deep into a subsystem or an external model, one owned surface absorbs the churn.
  *Not when:* it would forward calls one-to-one and absorb nothing — a middle man.

## Application and service altitude

- **Externalize environment-varying values** — hardcoded endpoints, credentials, paths, tunables
  move to the platform's configuration mechanism with safe defaults. The test is variance: a
  value that genuinely differs per environment/operator is config; one that never varies stays
  inline (a knob nothing turns is speculative coupling to a future that has not arrived).
- **Introduce events / mediator / pub-sub for many-to-many knowledge** — when N components each
  know M others by name, or a workflow hardcodes its observers, publish domain events and let
  subscribers register. This trades knowledge-of-identity for message coupling.
  *Not when:* the flow is a simple one-to-one call — events there destroy traceability for
  nothing. Watch the mediator itself: a mediator that accretes orchestration logic becomes the
  god object it was meant to prevent, with every module now coupled to *it*.
- **Own the contract between applications** — implicit JSON shapes, shared DTO libraries
  compiled into both sides, and shared databases become explicit versioned contracts (schema,
  API version, published events) evolved expand-and-contract: add the new shape, migrate
  consumers, retire the old shape only when nothing reads it.
- **Break temporal coupling deliberately, not reflexively** — a synchronous chain where both
  sides must be up simultaneously can move to queued/eventual messaging, at the price of
  eventual consistency and a harder failure model. Reach for it on evidenced availability or
  scaling pressure, not because asynchrony is "more decoupled".

## Repository and document altitude

- **Point, don't copy** — copied code or prose that must track a living source becomes a
  reference to that source (a dependency on a released artifact, a link to the owning doc, a
  generated include). If a copy must exist (vendoring, a snapshot), mark it as a copy with its
  source and sync trigger so drift is detectable.
- **Depend on releases, not internals** — a repo consuming another repo pins a published,
  versioned artifact (package, tag, contract file), never a branch head, an internal path, or
  a file layout the owner may reorganize freely.
- **Extract the single source of truth** — a fact stated in N documents gets one owner; the
  other N-1 sites cite it. Derivable content (counts, inventories, tables of contents) is
  generated or dropped, never hand-maintained in parallel.
  *Not when:* the "duplicate" is a deliberate snapshot (a point-in-time record, an immutable
  decision log) — those are records, not copies.
- **Stabilize the link target** — deep references into another artifact's private structure
  (line numbers, section positions, internal file paths) move to stable entry points: anchors
  the owner declares, published names, or the artifact's root with the reader trusted to
  navigate.

## Sequencing rule

Prefer the smallest mechanism that removes the change-transmission: rename/localize before
parameterize, parameterize before interface, interface before event, event before new
process/service boundary. Every step up that ladder buys decoupling with indirection, and
indirection is a real cost — paid on every read. Stop climbing at the first rung that stops the
change from propagating.
