# Remediation catalog

Mechanism per finding kind, each with its counterweight. Decoupling has its own failure mode:
indirection added where no change pressure exists. Every entry therefore states when NOT to
apply it. An abstraction earns its place at a volatile or substitutable boundary; wrapping a
stable dependency in an interface is not decoupling, it is a second thing to maintain that
moves in lockstep with the first. The coupling remains, plus a layer.

## Code and module altitude

- **Inject the dependency (DI / Hollywood Principle)**: for hard-wired construction of a
  volatile collaborator, service-locator pulls, singletons smuggling state. Constructor
  injection first; let the composition root own wiring.
  *Not when:* the dependency is a stable value object or pure function. Injecting those is
  ceremony.
- **Extract an owned interface at the volatile boundary**: for direct references to
  third-party libraries, infrastructure, transport, or anything with a realistic second
  implementation (including a test double that genuinely needs to differ from the real thing).
  The interface belongs to the consumer's side and speaks the consumer's vocabulary
  (ports-and-adapters), not a mirror of the vendor API.
  *Not when:* one implementation, in-process, stable, and tests run fine against the real
  instance. An interface with a single implementation and an identical surface is needless
  indirection, not loose coupling.
- **Replace control coupling with separate operations or polymorphism**: a boolean/mode
  parameter switched on inside becomes two methods, a strategy, or a lookup; a type-code switch
  duplicated across sites becomes polymorphic dispatch or a registration table. When each case
  already lives in its own file or folder, a hand-kept table naming those files is a second
  list: discover or generate it instead (see "Second lists").
  *Not when:* the switch exists once, is closed by construction (exhaustive over a sealed set),
  and reads clearly. One honest switch beats a class-per-case explosion.
- **Weaken the connascence**: positional arguments → named/keyword or a parameter object;
  magic values → named constants or types; duplicated algorithms (validation, serialization,
  hashing) → one shared implementation both sides call; implicit ordering → an API that makes
  the order unrepresentable (builder that only yields a valid object, state machine types).
- **Move behavior to the data it envies**: feature envy and reach-through chains resolve by
  relocating the calculation onto the type that owns the state, or by asking the collaborator
  ("tell, don't ask") instead of interrogating its graph.
- **De-globalize shared mutable state**: common coupling via statics/singletons becomes an
  injected instance whose lifetime the composition root owns; shared config objects become
  read-only snapshots handed in.
- **Facade / anti-corruption layer over a messy or foreign surface**: when many call sites
  each reach deep into a subsystem or an external model, one owned surface absorbs the churn.
  *Not when:* it would forward calls one-to-one and absorb nothing. That is a middle man.

## Application and service altitude

- **Externalize environment-varying values**: hardcoded endpoints, credentials, paths, tunables
  move to the platform's configuration mechanism with safe defaults. The test is variance: a
  value that genuinely differs per environment/operator is config; one that never varies stays
  inline (a knob nothing turns is speculative coupling to a future that has not arrived). The
  cross-cutting rule text lives in `docs/plugin-philosophy.md` § Design boundary → **Hardcoded
  consumer specifics**; this catalog keeps the remediation mechanism only.
- **Introduce events / mediator / pub-sub for many-to-many knowledge**: when N components each
  know M others by name, or a workflow hardcodes its observers, publish domain events and let
  subscribers register. This trades knowledge-of-identity for message coupling.
  *Not when:* the flow is a simple one-to-one call. Events there destroy traceability for
  nothing. Watch the mediator itself: a mediator that accretes orchestration logic becomes the
  god object it was meant to prevent, with every module now coupled to *it*.
- **Own the contract between applications**: implicit JSON shapes, shared DTO libraries
  compiled into both sides, and shared databases become explicit versioned contracts (schema,
  API version, published events) evolved expand-and-contract: add the new shape, migrate
  consumers, retire the old shape only when nothing reads it.
- **Break temporal coupling deliberately, not reflexively**: a synchronous chain where both
  sides must be up simultaneously can move to queued/eventual messaging, at the price of
  eventual consistency and a harder failure model. Reach for it on evidenced availability or
  scaling pressure, not because asynchrony is "more decoupled".

## Repository and document altitude

- **Point, don't copy**: copied code or prose that must track a living source becomes a
  reference to that source (a dependency on a released artifact, a link to the owning doc, a
  generated include). If a copy must exist (vendoring, a snapshot), mark it as a copy with its
  source and sync trigger so drift is detectable.
- **Depend on releases, not internals**: a repo consuming another repo pins a published,
  versioned artifact (package, tag, contract file), never a branch head, an internal path, or
  a file layout the owner may reorganize freely.
- **Extract the single source of truth**: a fact stated in N documents gets one owner; the
  other N-1 sites cite it. Derivable content (counts, inventories, tables of contents) is
  generated or dropped, never hand-maintained in parallel.
  *Not when:* the "duplicate" is a deliberate snapshot (a point-in-time record, an immutable
  decision log). Those are records, not copies.
- **Stabilize the link target**: deep references into another artifact's private structure
  (line numbers, section positions, internal file paths) move to stable entry points: anchors
  the owner declares, published names, or the artifact's root with the reader trusted to
  navigate.

## Duplicate writers

- **Give the value one writer**: for a duplicate writer (the model's common-coupling entry),
  name one owner for the key, path or table; every other writer either calls the owner or
  becomes a reader. This is route lane by definition: choosing the owner is a design decision,
  and moving a write changes behavior when the writers disagree today.
  *Not when:* the writers are the same owner split across layers (a migration that seeds a table
  the owning service then writes), or the value is append-only by design (a log both sides add
  lines to, with no line ever rewritten).
- **Hand off the ownership rule.** Once phase C confirms a duplicate writer, the rule that
  keeps it at one writer ("only `<owner>` writes `<value>`") goes to a findings file so a
  deterministic check can be proposed for it:
  - Write one file in the review-findings shape (frontmatter `type: review-findings`, a
    `## Findings` table), defined at
    <https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/plugins/review/reference/findings-file-shape.md>.
    One row per confirmed duplicate writer: `Location` is one write site outside the proposed
    owner, `Finding` names the value and its other write sites, `Action` states the ownership
    rule. Untrusted text (paths, values) stays in the cells, escaped per that file.
  - Write it under `<memory_dir>/coupling/<branch-slug>/`, where `<memory_dir>` is the memory
    root the ledger lives under (`.work/` by default) and `<branch-slug>` is the branch name
    lowercased with every character outside `[a-z0-9._-]` replaced by `-`. Never write under
    `<memory_dir>/reviews/`: the file is for the enforceability audit, not the review fix action.
  - Follow the memory-tier write discipline: announce the path before writing; on the first
    write, verify the memory root holds a `.gitignore` containing `*`, creating it (announced)
    when absent; never edit the consumer's root `.gitignore`; write nothing when the memory root
    is the repository root, and report the rows instead.
  - The ledger entry's `outcome` and the run's report both name the file. When
    `/review:audit-enforceability` is among the available skills, the report offers
    `/review:audit-enforceability <file>`; it never invokes that skill unasked. Without it, the
    report names the file and the proposed rule only.

## Second lists

A second list is a hand-kept file whose entries each name a file or folder the tree already holds:
a plugin registry, a route table, a list of copied files. Every new entry edits it, so parallel
changes collide on it, and an entry can outlive the file it names. `derivable-list.py` flags one
among the ranked hotspots (SKILL.md phase B). It is report-only: a second list goes to the route
lane, never into the apply batch, and the consumer picks the remedy.

Report each confirmed second list as a Design-It-Twice comparison: the three designs below, each
judged for this list on the same three questions, then one recommendation the human may reject.

| Design | A new entry costs | Drift is caught by | Needs |
|---|---|---|---|
| **Keep the list** | one edit to the shared file beside the new folder | nothing until something reads the dangling entry | nothing |
| **Discover at build time** | the new folder alone | the loader, at the next build or start | a stack with a loader that reads a folder (a glob import, a plugin scan, a file-based router) |
| **Generate the list, check for drift** | the new folder, then a regenerate step | a `--check` run in the consumer's CI that fails when the file differs from a fresh generation | a generator script and one CI step |

- **Keep the list.** *Fits when* entries carry data the tree does not hold (an order, a category,
  a display name) and new entries are rare, or a tool outside the consumer's control reads the file
  in this exact shape. *Not when* the hotspot run shows parallel changes conflicting on it.
- **Discover at build time.** The tree is the only list; each folder's own reserved file (an
  index, a manifest) carries what an entry used to. *Not when* the stack has no loader that reads
  a folder, or a published file must exist for outside readers. Adding a bundler or a framework to
  get one is a larger change than the coupling it removes.
- **Generate the list, check for drift.** The file stays where outside readers expect it, but no
  one edits it by hand: a script writes it from the tree and per-folder files, and `--check` fails
  CI when the file and a fresh generation differ. Needs no bundler, so it fits any stack. This repo
  applies the form to its plugin catalog:
  <https://github.com/melodic-software/claude-code-plugins/blob/main/scripts/generate-catalog.mjs>
  (header lines 3-7: generated block, `--check` as the CI gate). *Not when* two generators would
  write the one file, which is a duplicate writer (see "Duplicate writers"). Parallel changes still
  touch the generated file; regenerating after a merge settles each conflict, so the file stops
  being a place for judgment.

Entry data the tree does not hold moves into each folder's own file before either discovery or
generation can replace the list; name that move in the report. A list a generator already writes
(a marker block, a header saying so, a `--check` step in CI) is the third design in place: report
it as already derived and do not ledger it.

## Sequencing rule

Prefer the smallest mechanism that removes the change-transmission: rename/localize before
parameterize, parameterize before interface, interface before event, event before new
process/service boundary. Every step up that ladder buys decoupling with indirection, and
indirection is a real cost, paid on every read. Stop climbing at the first rung that stops the
change from propagating.
