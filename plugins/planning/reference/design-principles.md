# Design principles

Scope: these principles apply to code, Markdown, skills and agent instructions alike.

Consumer standards win: where the consumer's own standards or instruction files contradict a
default here, apply the consumer's rule and record
`Overrides bundled default <principle> per <standards file>`.

Each line is a default the user can decline. Its source is the primary that defines the principle,
or a labeled secondary where the primary could not be fetched.

## Principles

- **SRP**: Give each module, file or skill one reason to change, where a reason is one person or
  group who asks for changes; in Markdown, keep text that different owners change in different
  files. Source: Robert C. Martin,
  [The Single Responsibility Principle](https://blog.cleancoder.com/uncle-bob/2014/05/08/SingleReponsibilityPrinciple.html)
  (2014). As of 2026-10-18; recheck when the post moves or changes.
- **OCP**: Add a variant by adding code, not by editing code that already works, at the variation
  points [`variation-points.md`](variation-points.md) names; in Markdown, add a reference file a
  hub points at rather than growing the hub. Source: Robert C. Martin,
  [The Open Closed Principle](https://blog.cleancoder.com/uncle-bob/2014/05/12/TheOpenClosedPrinciple.html)
  (2014), crediting Bertrand Meyer (1988). As of 2026-10-18; recheck when the post moves or
  changes.
- **LSP**: A subtype, implementation or substitute keeps every promise of the contract it stands
  in for, so callers never check which one they hold; in Markdown, a skill that replaces another
  accepts the same arguments and returns the same shape. Source: Barbara Liskov and Jeannette
  Wing, [A Behavioral Notion of Subtyping](https://www.cs.cmu.edu/~wing/publications/LiskovWing94.pdf),
  ACM TOPLAS (1994), §1, the Subtype Requirement. As of 2026-10-18; recheck when the hosted copy
  moves.
- **ISP**: Give each client an interface holding only what it uses, split by caller role; in
  Markdown, split a reference whose readers each need a different part, so each loads only its
  part. Source: Robert C. Martin,
  [Design Principles and Design Patterns](https://web.archive.org/web/20150906155800if_/http://www.objectmentor.com/resources/articles/Principles_and_Patterns.pdf)
  (2000), section "The Interface Segregation Principle (ISP)". As of 2026-10-18; recheck when the
  archived copy moves or Martin republishes the paper.
- **DIP**: Make high-level policy depend on abstractions it owns and let the details implement
  them, never the reverse; in Markdown, a generic skill names the capability it needs, not one
  vendor's tool. Source: Robert C. Martin,
  [Design Principles and Design Patterns](https://web.archive.org/web/20150906155800if_/http://www.objectmentor.com/resources/articles/Principles_and_Patterns.pdf)
  (2000), section "The Dependency Inversion Principle (DIP)". As of 2026-10-18; recheck when the
  archived copy moves or Martin republishes the paper.
- **Composition over inheritance**: Build behavior by combining parts rather than extending a
  base whose internals the extension then depends on, and inherit only for a true subtype (LSP);
  in Markdown, compose a skill from referenced files rather than copying and editing a parent.
  Source (secondary): Graham Lee,
  [When did people favor composition over inheritance?](https://www.sicpers.info/2025/11/when-did-people-favor-composition-over-inheritance/)
  (2025), quoting the second object-oriented design principle of Gamma, Helm, Johnson and
  Vlissides, *Design Patterns* (1st ed., 1994), ch. 1. As of 2026-10-18; recheck when the cited
  secondary moves or changes, or a recheck reaches the primary.
- **DRY of knowledge**: Give each fact, rule, value or decision one authoritative home and point
  every other place at it; DRY targets repeated knowledge, not similar-looking text. In Markdown,
  state a fact once and link to it. Source: Dave Thomas in
  [Orthogonality and the DRY Principle](https://www.artima.com/articles/orthogonality-and-the-dry-principle),
  Artima interview with Andy Hunt and Dave Thomas (2003). As of 2026-10-18; recheck when the
  interview page moves or changes.
- **Coupling and cohesion**: Keep what changes together in one module and minimize what modules
  must know about each other, so one change stays in one place; in Markdown, a skill cites another
  by its `/plugin:skill` name, never by a path into its files. Source (secondary): IEEE Computer
  Society, [Larry L. Constantine](https://history.computer.org/pioneers/constantine.html) pioneer
  profile, first published in 1968 and repeated in the widely cited 1974 paper by Stevens, Myers
  and Constantine, "Structured Design", *IBM Systems Journal* 13(2).
  As of 2026-10-18; recheck when the cited secondary moves or changes, or a recheck reaches the
  primary.
- **Information hiding**: Decompose around the decisions most likely to change and hide each
  behind one module's interface, so changing it touches one module; in Markdown, keep a volatile
  upstream specific behind one pointer rather than restating it. Source: David L. Parnas,
  [On the Criteria To Be Used in Decomposing Systems into Modules](https://wstomv.win.tue.nl/edu/2ip30/references/criteria_for_modularization.pdf),
  *Communications of the ACM* (1972), Conclusion. As of 2026-10-18; recheck when the hosted copy
  moves.
- **Deep modules and change amplification**: Prefer modules whose small interface hides much
  functionality, and treat a simple change that needs edits in many places as a design defect,
  fixed by moving the repeated knowledge behind one module; in Markdown, changing one fact should
  mean editing one file. Source: John Ousterhout, Stanford CS190 notes
  [Modular Design](https://web.stanford.edu/~ouster/cgi-bin/cs190-winter18/lecture.php?topic=modularDesign)
  and [Complexity](https://web.stanford.edu/~ouster/cgi-bin/cs190-winter18/lecture.php?topic=complexity)
  (Winter 2018). As of 2026-10-18; recheck when the course pages move or change.
- **YAGNI cheap-now test**: Build no capability for a presumptive feature; build ahead only when
  it is cheap now, adds little complexity and significantly cuts later cost. Work that makes the
  code easier to change is never speculative. Source: Martin Fowler,
  [Yagni](https://martinfowler.com/bliki/Yagni.html) (2015). As of 2026-10-18; recheck when the
  bliki entry moves or changes.
- **Reuse first**: Search for and reuse existing code, references and skills before writing new
  ones. Whether to generalize now or wait for real duplication is a per-task question for the
  user, answered from expected repetition or per-client variation, the product's existing
  structure, and upstream context. With known repetition or variation, generalize up front and
  isolate what varies; otherwise extract on the third occurrence (the Rule of Three), and when an
  abstraction stops fitting, inline it back into its callers rather than adding conditionals.
  Source: Sandi Metz, [The Wrong Abstraction](https://sandimetz.com/blog/2016/1/20/the-wrong-abstraction)
  (2016); Rule of Three (secondary):
  [Rule of three (computer programming)](https://en.wikipedia.org/wiki/Rule_of_three_(computer_programming)),
  attributing it to Don Roberts in Fowler et al., *Refactoring* (1st ed., 1999).
  As of 2026-10-18; recheck when Metz's post moves or changes, or, for the Rule of Three, the
  cited secondary moves or changes, or a recheck reaches the primary.

## Review time

Review-time criteria and severities for these principles belong to
`/review:quality-gate code-design`; this file sets design-time defaults only.

## Markdown and skill authoring

No separate rule applies here. For repeated prose, use `/docs-hygiene:extract-ssot`. For skill
text, use `/playbooks:skill-authoring`; for agent-loaded Markdown, use `/docs-hygiene:write-for-agents`.
