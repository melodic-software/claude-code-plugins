# Deepening Vocabulary

Shared vocabulary for every suggestion the `deepening` lens makes. Use these terms exactly — consistent language is the point.

Source: Ousterhout's "A Philosophy of Software Design", adapted for practical use.

## Terms

**Module** — anything with an interface and an implementation. Scale-agnostic: function, class, package, vertical slice. Avoid: unit, component, service.

**Interface** — everything a caller must know to use the module correctly. Includes type signature, invariants, ordering constraints, error modes, required configuration, performance characteristics. Avoid: API, signature (too narrow — type-level surface only).

**Implementation** — what's inside a module. Distinct from **Adapter**: a thing can be a small adapter with a large implementation (Postgres repo) or a large adapter with a small implementation (in-memory fake). Use "adapter" when the seam is the topic; "implementation" otherwise.

**Depth** — leverage at the interface. A module is **deep** when large behavior sits behind a small interface. A module is **shallow** when the interface is nearly as complex as the implementation.

**Seam** (Feathers) — a place where behavior can be altered without editing in that place. The location at which a module's interface lives. Choosing seam placement is its own design decision, distinct from what goes behind it. Avoid: boundary (overloaded with DDD's bounded context).

**Adapter** — a concrete thing satisfying an interface at a seam. Describes role (what slot it fills), not substance (what's inside).

**Leverage** — what callers get from depth. More capability per unit of interface they must learn. One implementation pays back across N call sites and M tests.

**Locality** — what maintainers get from depth. Change, bugs, knowledge, and verification concentrate at one place rather than spreading across callers.

## Principles

- **Depth is a property of the interface, not the implementation.** A deep module can be internally composed of small, mockable, swappable parts — they just aren't part of the interface. A module can have **internal seams** (private, used by own tests) and **external seams** (at its interface).
- **The deletion test.** Imagine deleting the module. If complexity vanishes, it was a pass-through. If complexity reappears across N callers, it was earning its keep.
- **The interface is the test surface.** Callers and tests cross the same seam. If you want to test *past* the interface, the module is probably the wrong shape.
- **One adapter = hypothetical seam. Two adapters = real seam.** Don't introduce a seam unless something actually varies across it.

## Relationships

- A **Module** has exactly one **Interface**
- **Depth** is a property of a **Module**, measured against its **Interface**
- A **Seam** is where a **Module**'s **Interface** lives
- An **Adapter** sits at a **Seam** and satisfies the **Interface**
- **Depth** produces **Leverage** for callers and **Locality** for maintainers

## Rejected framings

- **Depth as ratio of implementation-lines to interface-lines** (Ousterhout literal) — rewards padding. We use depth-as-leverage
- **"Interface" as TypeScript `interface` keyword or class's public methods** — too narrow; interface includes every fact a caller must know
- **"Boundary"** — overloaded with DDD bounded context. Use **seam** or **interface**
