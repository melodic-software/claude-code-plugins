# Variation points: design for variation, contain by default

The shared rule this plugin applies wherever a design picks one variant of something that has, or
may have, others. `/planning:design` runs the pass and records a verdict per variation point, and
`/planning:plan` audits that every external integration carries one. An intent answer already
recorded in the Brief (must this be generic, is the next variant known?) is a settled input to
the first question. This file states the principles in general terms and points at the
canonical sources for the patterns; it carries no worked code and no stack-specific recipe.
Applying a pattern to the solution in hand is the design step's job, grounded in those sources
and the solution's own conventions.

## What a variation point is

A place where the design commits to one variant of:

- **an external system**: an identity or sign-in provider, a payment gateway, a records system,
  a notification channel, a content platform, any service or store the solution does not own;
- **a domain category**: a kind of thing the domain already names as a family (component types,
  document kinds, channels), even when only one member is being built.

Every external integration is a variation point, whether or not a second variant is in sight.
An internal one-off with no category behind it is not one.

## The two questions

Ask both for each variation point, and record each answer with its `Basis:` per
[`../context/recommendation-basis.md`](../context/recommendation-basis.md).

1. **How likely is a second variant?**
   - **known**: a second variant is named in the Brief, the roadmap, the issue, or the code;
   - **category**: the domain names a category the variant belongs to, so more are expected;
   - **speculative**: nothing says another is coming.
2. **How costly is a change after shipping?**
   - **code only**: callers inside the solution; a refactor reaches every one;
   - **durable**: stored data and schema, published contracts, messages, or external consumers;
     a change needs a migration or a coordinated release.

Evidence for the first comes from the Brief, the domain vocabulary, and the tracker; for the second, from what the design stores and exposes. A guess is labeled
`Basis: judgment`, never presented as a fact.

## The three verdicts

| Verdict | Shape | When |
|---|---|---|
| **Abstract now** | a seam named in domain words with the variants behind it: ports and adapters, a Gateway, a plugin or registry | only on a human's answer (see "Autonomy"), or when the Brief itself requires two variants now |
| **Contain now, abstract later** | the provider code sits in one module; names, types and storage at that module's boundary are provider-neutral | the default for anything external; cheap, reversible, and adds no speculative extension point |
| **Leave inline** | no boundary of its own | internal one-offs only: no external system, no named category, a code-only change cost |

**Contain is not a weaker abstraction.** It hides one decision likely to change behind one
module, which is information hiding, and it keeps the later move to "abstract" a code-only
refactor: provider names never reach the domain model, the schema, or a public contract, so the
expensive half of the change cost stays at zero. A provider's own identifiers, when they must be
stored, are stored as data under neutral names, never as schema or contract names.

**Never leave an external system inline.** Its name in domain code, storage, or an API is the
closed design this rule exists to catch, and it is the costly kind to undo.

**When the Brief requires two variants now**, the seam is a requirement, not a verdict the agent
chose: record it as abstract with the Brief as its basis.

## The leak test

Apply it to every abstraction and to every contained module's boundary. Each check is a pass or
a named failure:

1. **Named for the consumer's need, in domain words**, not for the provider or the technology.
2. **No implementation types in its signatures**: no provider SDK, driver, ORM, transport, or
   framework type crosses it.
3. **No implementation verbs unless they are domain concepts**: the operations say what the
   consumer needs done, not how the provider does it.
4. **Swapping the implementation would not change it**: a second provider would fit behind the
   same names, types, and storage.

A failed check is a design thread: rename or re-type the seam in the consumer's terms, or record
why the leak is accepted. An abstraction copied from a popular template, sample, or repository
gets the same test; its popularity is adoption, not evidence that it passes (the "Popularity is
not correctness" rule in the recommendation-basis contract).

## Autonomy

An agent never chooses **abstract** on its own.

- **Interactive.** Ask the abstraction question, recommending **contain**, and name in the
  question the evidence that would favor abstract now (a known variant with a durable change
  cost). Record abstract only on the user's answer.
- **Unattended** (declared by the caller, never sniffed): apply **contain** and record the
  abstraction question as a human decision. In `/planning:design` the thread is **resolved** with
  the contain verdict and its rationale (safe whatever the answer), and lists the reserved
  question inside it, tagged `arbiter: USER-RESERVED`, for the user to answer later; when the work
  is tracked, the tracked item also carries the tracker's needs-decision status
  (`status:needs-decision` in the `/work-items:track` label taxonomy). Because contain holds either
  way, the question never blocks the run or the design handoff.

## Respect the existing architecture style

Detect the solution's style before placing a seam, from the solution itself: its project and
folder layout, the dependency direction its references show, its ADRs, its architecture tests or
analyzer rules, and its own rules and standards. Common styles are vertical-slice-only, modular
monolith, clean architecture, or a hybrid of them. Place the containing module or the seam where
that style already puts code that talks to the outside; this rule imposes no layout of its own.
When the signals conflict or are absent, the placement is a design thread, not a default.

**Lookalike models stay separate.** Contexts whose models look alike but mean different things
stay duplicated; merging them into one shared abstraction couples contexts that change for
different reasons.

## Canonical sources

The verdicts and the leak test rest on these. Cite the source when a design applies a pattern;
fetch the page when a definition needs verifying (a book cited from recall is recall).

- **Information hiding**: D. L. Parnas, "On the Criteria To Be Used in Decomposing Systems into
  Modules", Communications of the ACM 15(12), 1972. The root of "contain": a module hides a
  design decision likely to change.
- **Design Patterns** (Gamma, Helm, Johnson, Vlissides, 1994): Adapter, Bridge, Strategy, Abstract
  Factory.
- **Patterns of Enterprise Application Architecture** (Fowler, 2002), catalog at
  <https://martinfowler.com/eaaCatalog/>: [Gateway](https://martinfowler.com/eaaCatalog/gateway.html),
  [Separated Interface](https://martinfowler.com/eaaCatalog/separatedInterface.html),
  [Plugin](https://martinfowler.com/eaaCatalog/plugin.html),
  [Registry](https://martinfowler.com/eaaCatalog/registry.html),
  [Service Stub](https://martinfowler.com/eaaCatalog/serviceStub.html). Fowler's
  [Gateway article](https://martinfowler.com/articles/gateway-pattern.html) grounds the leak test:
  the gateway's interface works in the terms the consuming system uses.
- **Enterprise Integration Patterns** (Hohpe, Woolf, 2003), catalog at
  <https://www.enterpriseintegrationpatterns.com/patterns/messaging/>: Messaging Gateway and
  Channel Adapter for message-based integrations.
- **Hexagonal architecture** (ports and adapters): A. Cockburn,
  <https://alistair.cockburn.us/hexagonal-architecture/>.
- **Domain-Driven Design** (Evans, 2004), summarized in the
  [DDD Reference](https://www.domainlanguage.com/ddd/reference/): Bounded Context, Context Map,
  Anticorruption Layer. **Implementing Domain-Driven Design** (Vernon, 2013). **Learning
  Domain-Driven Design** (Khononov, 2021).
- **Change likelihood as a coupling dimension** (volatility): Khononov, **Balancing Coupling in
  Software Design** (2024), <https://coupling.dev/>.
- **Why contain is not speculative**: Fowler, [Yagni](https://martinfowler.com/bliki/Yagni.html):
  yagni excludes presumptive features, not effort that makes the software easier to modify.
- **Architecture styles**: Bogard,
  [Vertical Slice Architecture](https://www.jimmybogard.com/vertical-slice-architecture/);
  Martin,
  [The Clean Architecture](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html);
  Grzybek, [Modular Monolith: A Primer](https://www.kamilgrzybek.com/blog/posts/modular-monolith-primer);
  Fowler, [Bounded Context](https://martinfowler.com/bliki/BoundedContext.html).

Links checked 2026-10-11. Recheck a link when it stops resolving or the page it names moves.
