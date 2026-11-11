# Active project-glossary contract

## Entry discipline

The consuming project's existing shape wins. A new Markdown glossary may use this minimal readable
fallback when the repository provides no entry convention:

```markdown
# Billing glossary

Terms the billing team uses. Avoid marks words we rejected; use the chosen term or verb instead.

**Invoice**

A request for payment issued to a customer after delivery.

States: Draft, then Sent, then Paid or Void.

Actions: void (Avoid: cancel)

Avoid: bill, payment request

Shown to users as: bill
```

- **Header sentence:** a new glossary says once, under its title, what `Avoid:` means. The line is
  plain on purpose; a hard ban belongs in a check (a spelling or lint rule generated from the
  rejected words on `Avoid:` and `Actions:` lines), not in emphatic wording.
- **Canonical term:** one preferred name for the concept within this bounded context.
- **Definition:** 1–2 sentences stating what the term is. Define its conceptual boundary, not its
  implementation, behavior backlog, or storage representation.
- **States:** one entry per entity, with its states listed under it and what moves it into each when
  that is part of the meaning. A state gets its own entry only when people use it as a noun on its own
  and it carries rules of its own. Omit the line when the entity has no named states.
- **Actions:** optional, under the entity like `States:`, only when one verb was chosen over another
  for an operation on it: the chosen verb, then the rejected one in parentheses, `Actions: submit
  (Avoid: raise)`; several contested operations are comma-separated pairs on one line. Omit the line
  when no verb was contested.
- **Rejected synonyms:** names considered and rejected for this concept. Follow the existing file's
  syntax; otherwise use the plain `Avoid:` line above. Omit the line when no synonym was rejected.
  The line holds only other names for the same concept: a word with a meaning of its own (a credit
  note beside an invoice) gets its own entry when the context uses it, or stays off the glossary.
- **Shown to users as:** optional, only when the wording on screens, emails and error messages
  deliberately differs from the term. Checks for rejected words treat this wording as intended.
  When tenants rename the concept on their own screens, the line reads `Shown to users as:
  configurable per tenant`: the context keeps one model term, the tenant words are configuration,
  never synonyms or `Avoid:` words, and a hit on one of them is not drift.
- **Admission:** project-context terms only. Generic programming or methodology vocabulary stays out
  unless it has a distinct project-domain meaning, and so do everyday words used in their ordinary
  sense. A term earns an entry only when it removes ambiguity in this context: a project-specific
  meaning, a clash between meanings, or a rejected synonym.
- **Purity:** the glossary contains vocabulary, not specifications, decisions, tasks, examples of
  implementation, or unresolved brainstorming.
- **One definition:** ADRs and docs use a term but never redefine it; the definition lives only in
  the glossary.
- **Business rules:** an entry says what the concept is, never what may or must happen to it ("an
  invoice over 10,000 needs a second approver" is a rule, not a definition). The rule lives in code (a type, a
  validation) and a test that names it; the reason for the rule goes in an architecture decision
  record when it passes `/architecture:record-decision`'s admission test.
- **Grouping:** when the terms fall into clear clusters, put each cluster under its own subheading;
  a small or uniform set stays one list.

Use scenarios to test whether the definition is precise enough for domain experts and developers to
use consistently. Update the language as understanding changes; do not preserve a stale entry merely
because it is already written.

## Counting a term

`audit` and `curate` count a term, a rejected synonym or a rejected verb one way, and a question
and its recap give the same numbers:

- Split identifiers at camelCase, PascalCase and snake_case boundaries, so `createShipment`,
  `ShipmentStatus` and `shipment_id` each hold the word `shipment`.
- Match whole words, case-insensitive; a multi-word term matches as consecutive words, so
  `paymentRequest` matches "payment request".
- Uses in the glossary and the glossary index do not count.
- Report the uses and the number of files: `Shipment: 7 uses in 3 files`.

## Convention-resolution ladder

Resolve both format and location in this order:

1. Explicit consumer configuration or repository rules, naming a path inside the current
   repository; a path outside it is ignored and never written.
2. An existing glossary and glossary index that cover the scope, found by `locate`'s repository
   search (a `docs/glossary.md` counts as much as a root `GLOSSARY.md`).
3. A single clear convention inferred from the repository's documentation layout and accepted domain
   artifacts; persist the inference by creating the first real entry in that shape.
4. Ask when two or more plausible choices remain. When the repository has no convention at all,
   propose the settings' file names, never impose them: one `glossary_file` (default `GLOSSARY.md`)
   per bounded context, at the root of that context's code and opening with a short description of
   the context, and one glossary index, `glossary_map_file` (default `GLOSSARY-MAP.md`), at the
   repository root once more than one context exists. Ask the user to confirm the proposal before
   writing.
5. If interaction is unavailable, defer creation and report the missing convention rather than baking
   in a universal filename or path. The report names the proposal; nothing is written.

The two file names come from the domain-driven-design settings, resolved by
`scripts/glossary-settings.mjs` (plugin root) through the config cascade: the plugin default,
`userConfig`, the team file `<home>/domain-driven-design.yaml` and the personal override
`<home>/domain-driven-design.local.yaml`, where `<home>` defaults to `docs/conventions`. Each value is
a file name, never a path. When proposing a name, say which layer supplied it (`provenance`), and name
any layer the script reports invalid.

Never create an empty glossary. Re-read before every write and preserve the consumer's structure.

## Domain only

The glossary holds the domain's language. Framework, library and tooling nouns belong in the
project's architecture docs, not the glossary, unless the domain gives them a distinct meaning.

## Multiple bounded contexts

Each established bounded context owns its own internally consistent language. A shared spelling may
therefore have separate definitions in separate context glossaries.

- Use an existing glossary index and per-context glossary placement when present.
- Create a glossary index only after multiple contexts are already established and actually own distinct
  languages. Infer its filename and shape from the consumer; ask when that is not unambiguous. With
  no convention, the question proposes `glossary_map_file` at the repository root.
- A minimal new glossary index records each known context, its glossary path, and only relationships already
  established by accepted project artifacts or the user.
- Route each entry to one context. If context is ambiguous, ask. Do not duplicate the entry as a hedge.
- Use a term bare inside its own context ("Policy" in Underwriting). Wherever contexts meet (the
  glossary index, integration code, cross-context docs), qualify it by its context ("Underwriting
  Policy", "Claims Policy").
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
