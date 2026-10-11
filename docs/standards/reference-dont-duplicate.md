# Reference, don't duplicate

Every fact has one source of truth. A consumer of that fact cites it; it never restates it. A one-line "summary" of someone else's rule is the cheapest thing to write and the most expensive to maintain: when the source changes, the copy silently drifts and readers can no longer tell which version is canonical. This is a reasoning-only discipline: a tool can flag candidate duplicates, but deciding whether two passages *mean* the same thing is a judgment.

## Two kinds of duplication

- **Literal**: a verbatim repeat of a value across files, such as a version pin, a port, a URL, a path, an identifier.
- **Semantic**: the same concept reworded: one rule explained three different ways across three files, one prerequisite described with different phrasing in four documents.

Literal duplication is easy to grep. Semantic duplication is the harder, equally costly smell: every update touches N sites, divergent phrasings produce silent contradictions, and readers cannot tell which is authoritative.

## Consolidation doctrine: ordered tests

When two passages look duplicated, copy-count thresholds are not the decision. The Rule of Three and "share at the second consumer" are heuristics subordinated to this ordered sequence: run the tests in order; the first decisive test wins.

1. **T1: Same knowledge or coincidental?** Identical text encoding different knowledge is a coincidence, not duplication ([Hunt/Thomas](https://media.pragprog.com/titles/tpp20/dry.pdf)); never consolidate, because consolidation actively harms.
2. **T2: Crosses an encapsulation boundary?** Bounded contexts, services, availability seams: duplication is correct by design ([DDD divergent models](https://martinfowler.com/bliki/BoundedContext.html); [event-carried state transfer](https://martinfowler.com/articles/201701-event-driven.html)). Consolidate only via an explicit shared-kernel-style decision with an owner.
3. **T3: Change-together acid test.** One fact forcing edits in multiple places or formats (including code+docs pairs) is true knowledge duplication: consolidate now, even at two copies; count is irrelevant ([Hunt/Thomas](https://media.pragprog.com/titles/tpp20/dry.pdf)).
4. **T4: Abstraction namable and stable?** Both must hold to consolidate at two copies. Cannot name it, or the shape is still changing → the [Rule-of-Three brake](https://blog.jbrains.ca/permalink/clarifying-the-rule-of-three-in-refactoring/) applies ([wrong-abstraction avoidance](https://sandimetz.com/blog/2016/1/20/the-wrong-abstraction)); namable **and** stable → two copies suffice.
5. **T5: Reversibility.** Cheap to inline back → early consolidation is low-risk; load-bearing/hard-to-unwind abstraction → demand the third occurrence as evidence ([Rainsberger](https://blog.jbrains.ca/permalink/clarifying-the-rule-of-three-in-refactoring/)).
6. **T6: Churn/friction.** High co-change frequency multiplies drift cost → consolidate earlier; static content tolerates copies longer ([DITA single-sourcing](https://docs.oasis-open.org/dita/dita/v1.3/errata02/os/complete/part1-base/archSpec/base/single-sourcing.html); [Write the Docs reuse caveats](https://www.writethedocs.org/conf/portland/2022/speakers/#speaker-anna-gasparyan-don-t-shoot-yourself-in-the-foot-with-content-reuse-anna-gasparyan)).

**Prose overlay:** knowledge-bearing docs content (values, procedures, policy) consolidates when T3–T6 say so. DITA single-sourcing is the mechanism for many deliverables from one source, not a first-reuse timing rule; audience-, context-, or SEO-sensitive prose is legitimately duplicated (Write the Docs reuse caveats); reuse-eligibility alone never justifies consolidation.

The Rule of Three is not a cost calculus: the claim that three copies makes maintenance cost definitively outweigh refactoring cost was refuted. It is a heuristic brake against premature wrong abstractions, permissive about two, never a prohibition on earlier extraction when T3–T6 say consolidate.

## Smell signals: any one triggers the doctrine

1. One change edits the same fact in multiple places or formats (including a code+docs pair): run T3.
2. A search finds near-matches saying almost-but-not-quite the same thing: run T1 before consolidating.
3. Two files assert the same rule with contradicting nuance: never leave both authoritative; run T1–T3.

## Classify a file's role before flagging

Each file plays one of three roles toward a given fact:

- **Describe**: the file *is* the source of truth and owns the value or concept. Keep the body here.
- **Use**: the file consumes the fact as a load-bearing reference (rules, conventions, internal docs). It must cite the source by a stable anchor rather than restate the content.
- **Expose**: the file surfaces the fact to humans for onboarding clarity (a README install command, an error message, a baseline snapshot). It *may* restate when onboarding clarity outweighs maintenance cost, and only when adjacent prose points back to the source so a future maintainer finds every copy.

## What stays inline versus what must be cited

**Stays inline (it is the contract surface, not duplication):** public names the source defines, such as severity tier names, label slugs, action verbs, command names, type identifiers. Naming a contract token is not copying it.

**Must be cited, never recapped:** definitions, criteria, "when to use" descriptions, mapping tables, examples, threshold numbers, and exception clauses, meaning anything specific and subject to change. A one-line recap drifts when the source updates; the citation alone is sufficient.

## Cite stable anchors

Cite a source by something durable: a file's documented heading, a configuration key, a published symbol, an anchor the source intends to keep stable. Avoid citing line numbers, incidental phrasing, or internal structure that the source is free to change without notice. Prefer a link the reader can follow over a prose reference they must hunt for.

## The code and config equivalent

The same discipline holds outside prose. Deduplicate with the language's idiomatic mechanism rather than copying a literal across call sites: a shared constant, a build property and its reference, a YAML anchor and alias, a JSON `$ref`, an environment variable with a default. A repeated literal is both the duplication and the missing name; the named constant deduplicates and documents in one move.

## History lives in version control

Where and when something came from is a fact the version-control history already owns. An origin or history aside in code, comments, configuration, or docs (a "ported from" note, an "added on <date>" comment) copies that fact into a second place nothing keeps current. Leave it out of explanatory prose, code, comments, and configuration; [`legacy-and-migration-debt.md`](https://github.com/melodic-software/standards/blob/main/conventions/engineering/legacy-and-migration-debt.md) covers the related case of prose that narrates a migration.

A record whose purpose is evidence keeps its dates and origins: a manifest's adoption, rollout, or canary notes, an architecture decision record, a component's admission evidence, a changelog. There the date is the evidence a decision rests on, not a copy of version-control history.

## Sources

- Hunt/Thomas, *The Pragmatic Programmer* (20th Anniv.) DRY chapter: [DRY excerpt (PDF)](https://media.pragprog.com/titles/tpp20/dry.pdf)
- Dave Thomas, Artima interview: [Orthogonality and the DRY Principle](https://www.artima.com/articles/orthogonality-and-the-dry-principle)
- Rule of Three: [Wikipedia](https://en.wikipedia.org/wiki/Rule_of_three_(computer_programming))
- Rainsberger: [Clarifying the Rule of Three](https://blog.jbrains.ca/permalink/clarifying-the-rule-of-three-in-refactoring/)
- Fowler: [Bounded Context](https://martinfowler.com/bliki/BoundedContext.html) (quoting Evans)
- Fowler: [What do you mean by "Event-Driven"?](https://martinfowler.com/articles/201701-event-driven.html)
- OASIS DITA 1.3: [Producing different deliverables from a single source](https://docs.oasis-open.org/dita/dita/v1.3/errata02/os/complete/part1-base/archSpec/base/single-sourcing.html)
- Gasparyan, WTD Portland 2022: [Don't shoot yourself in the foot with content reuse](https://www.writethedocs.org/conf/portland/2022/speakers/#speaker-anna-gasparyan-don-t-shoot-yourself-in-the-foot-with-content-reuse-anna-gasparyan)

Further reading (links only, not load-bearing until a targeted primary-source verify pass): [Metz, *The Wrong Abstraction*](https://sandimetz.com/blog/2016/1/20/the-wrong-abstraction); [Dodds, AHA Programming](https://kentcdodds.com/blog/aha-programming); [Swett, counter-argument to Metz](https://www.codewithjason.com/duplication-cheaper-wrong-abstraction/); [Go proverb, copy a little](https://go-proverbs.github.io/).

## Related

- Whether a page may exist at all, the admission test upstream of this discipline: see `documentation-existence.md`.
- Citing authorities *outside* the repo (vendor docs, framework references): see `documentation-and-citations.md`.
- Resolving derivable external state instead of copying a snapshot of it: see `legacy-and-migration-debt.md` for the current-form-only posture.
