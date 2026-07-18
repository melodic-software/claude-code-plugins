# Active project-glossary contract

## Entry discipline

The consuming project's existing shape wins. A new Markdown glossary may use this minimal readable
fallback when the repository provides no entry convention:

```markdown
**Invoice**

A request for payment issued to a customer after delivery.

Avoid: bill, payment request
```

- **Canonical term:** one preferred name for the concept within this bounded context.
- **Definition:** 1–2 sentences stating what the term is. Define its conceptual boundary, not its
  implementation, behavior backlog, or storage representation.
- **Rejected synonyms:** names considered and rejected for this concept. Follow the existing file's
  syntax; otherwise use the plain `Avoid:` line above. Omit the line when no synonym was rejected.
- **Admission:** project-context terms only. Generic programming or methodology vocabulary stays out
  unless it has a distinct project-domain meaning.
- **Purity:** the glossary contains vocabulary, not specifications, decisions, tasks, examples of
  implementation, or unresolved brainstorming.

Use scenarios to test whether the definition is precise enough for domain experts and developers to
use consistently. Update the language as understanding changes; do not preserve a stale entry merely
because it is already written.

## Convention-resolution ladder

Resolve both format and location in this order:

1. Explicit consumer configuration or repository rules.
2. The nearest applicable existing glossary and context-map convention.
3. A single clear convention inferred from the repository's documentation layout and accepted domain
   artifacts; persist the inference by creating the first real entry in that shape.
4. Ask when two or more plausible choices remain.
5. If interaction is unavailable, defer creation and report the missing convention rather than baking
   in a universal filename or path.

Never create an empty glossary. Re-read before every write and preserve the consumer's structure.

## Multiple bounded contexts

Each established bounded context owns its own internally consistent language. A shared spelling may
therefore have separate definitions in separate context glossaries.

- Use an existing context map and per-context glossary placement when present.
- Create a map only after multiple contexts are already established and actually own distinct
  languages. Infer its filename and shape from the consumer; ask when that is not unambiguous.
- A minimal new map records each known context, its glossary path, and only relationships already
  established by accepted project artifacts or the user.
- Route each entry to one context. If context is ambiguous, ask. Do not duplicate the entry as a hedge.
- Do not infer new boundaries or relationships. Context discovery belongs to a separate modeling or
  EventStorming workflow.

## Research basis

- Eric Evans' [Domain-Driven Design Reference](https://www.domainlanguage.com/wp-content/uploads/2016/05/DDD_Reference_2015-03.pdf)
  defines ubiquitous language within an explicitly bounded context, treats a language change as a
  model change, and describes a context map as the terrain of already-identified models and contacts.
- Martin Fowler's [Ubiquitous Language](https://martinfowler.com/bliki/UbiquitousLanguage.html)
  emphasizes a rigorous common language that evolves with domain understanding.
- Fowler's [Bounded Context](https://martinfowler.com/bliki/BoundedContext.html) explains why large
  domains need multiple internally consistent models and vocabularies.
