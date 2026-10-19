# Lifecycle and reversibility

Read by `/planning:design` "Lifecycle and reversibility". Every call here is a recommendation the
user can decline. A consumer standard that sets its own architecture style, decision-record rule or
investment rule wins: apply it and record `Overrides bundled default <principle> per <standards file>`.
Stumble: no planning step weighed how hard a decision is to undo or how much design a part of the
domain deserves, so a reversible choice got the same deliberation as a public contract, and one-way
choices went unrecorded.

## Depth by quality bar

Read the `Quality bar:` line under the Brief's `### Captured assumptions`; with none, use
`production` and say so in the round.

| Quality bar | Door calls | Baseline and greenfield slice | Subdomain investment |
|---|---|---|---|
| `prototype` | skipped, named as deferred | skipped | skipped |
| `internal` | one-way doors only | applies | skipped |
| `production` | every significant decision | applies | applies |

A prototype records one TAGGED-DEFERRED thread in `design-threads.md`,
`Lifecycle and reversibility: deferred (prototype) [RESEARCH: make the door calls if it heads for production]`,
and the round says that reversibility was skipped and deferred.

## One-way and two-way doors

A significant decision is one that other modules, stored data, published contracts or other teams
will build on. Call each one a door and record the call in its thread as `Door: one-way` or
`Door: two-way`:

- **One-way door**: undoing it needs a data migration, a coordinated release or a rewrite (a stored
  format, a public contract or API, a module boundary others build on, a vendor commitment). Design
  it deliberately: write the criteria first, and run the Phase 2 two-candidate step when its other
  triggers hold. Prompt for an
  ADR: when the thread resolves, offer `/architecture:record-decision` (when that plugin is
  enabled) and note the offer in the thread. Unattended, list the ADR prompt in the run's output.
- **Two-way door**: undoing it is a code-only change. Decide it fast, with a recommendation and its
  `Basis:` line; no ADR prompt.

When the evidence cannot settle the call, treat the decision as a one-way door.

Source: Jeff Bezos, 2015 letter to shareowners,
[Amazon.com exhibit 99.1 to SEC Form 8-K](https://www.sec.gov/Archives/edgar/data/1018724/000119312516530910/d168744dex991.htm)
(filed 2016), the passage on Type 1 and Type 2 decisions. As of 2026-10-18; recheck when the filing
URL moves.

## Baseline: the consumer's style

With existing code, the baseline is the architecture style the solution already uses, detected as
[`<plugin-root>/reference/variation-points.md`](../../../reference/variation-points.md) "Respect the
existing architecture style" describes. A new design follows it; departing from it is a one-way
door with its own thread.

Greenfield, with no existing structure, recommend starting from one vertical slice: one feature
built end to end through every layer it needs, to clean internal quality (clear names, tests at
its seam, no cruft). This is a default the user can override with any style. While it is the only
slice it is a two-way door; once other slices build on the style, changing it is a one-way door,
so record it then with an ADR prompt. Unattended, record the slice as a captured assumption in its
thread with a revisit trigger, never as `blocked`. Stumble: agents on greenfield work pick an
architecture style by habit and build a full layered skeleton before any slice runs end to end; the
interview recorded no style decision for design to read.

Sources: Jimmy Bogard,
[Vertical Slice Architecture](https://www.jimmybogard.com/vertical-slice-architecture/) (2018);
Martin Fowler,
[Is High Quality Software Worth the Cost?](https://martinfowler.com/articles/is-quality-worth-cost.html#HighQualitySoftwareIsCheaperToProduce)
(2019), "High quality software is cheaper to produce". As of 2026-10-18; recheck when either page
moves or changes.

## Investment by subdomain

Classify each part of the domain the design touches and scale design effort to its type:

| Subdomain | What it is | Design investment |
|---|---|---|
| Core | what sets the product apart | most: a deep model, the two-candidate step on its contracts, the strongest tests |
| Supporting | needed and specific to this business, but no differentiator | adequate: the simplest design that fits, contained, no speculative extension points |
| Generic | solved the same way everywhere | least: adopt or buy a proven solution, contained behind a boundary per the variation-point pass |

Which subdomain is core is the business's call: recommend a classification with its `Basis:` and
record the user's answer in the thread.

The three-way split is Vernon's and Khononov's; Evans's DDD Reference names only Core Domain and
Generic Subdomains. Sources:

- Eric Evans,
  [Domain-Driven Design Reference](https://www.domainlanguage.com/wp-content/uploads/2016/05/DDD_Reference_2015-03.pdf)
  (2015), Distillation: "Core Domain" and "Generic Subdomains".
- Vaughn Vernon, *Implementing Domain-Driven Design* (Addison-Wesley, 2013), ch. 2, "Focus on the
  Core Domain"; the publisher's
  [sample pages](https://ptgmedia.pearsoncmg.com/images/9780321834577/samplepages/0321834577.pdf)
  carry the contents and the index entries for Supporting and Generic Subdomains.
- Vlad Khononov,
  [*Learning Domain-Driven Design*](https://www.oreilly.com/library/view/learning-domain-driven-design/9781098100124/)
  (O'Reilly, 2021), ch. 1, "Types of Subdomains" (secondary for the chapter contents: a
  [bookseller listing](https://www.schweitzer-online.de/ebook/Khononov/Learning-Domain-Driven-Design/9781098100100/A62801026/),
  because the publisher page refuses an unauthenticated fetch).

As of 2026-10-18; recheck when a cited page moves or changes, or a recheck reaches Khononov's
chapter through the publisher.
