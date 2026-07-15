# Project glossary — committed vocabulary record

The project glossary is the committed, repo-tracked record of resolved domain vocabulary. Design sessions read it before naming and write to it the moment a term resolves. Its job is twofold: define what each term IS, and pin the synonyms that were rejected so they stop resurfacing.

## Entry format

One term per entry:

```markdown
**Invoice**:
A request for payment issued to a customer after delivery.
Avoid: bill, payment request
```

- **Definition**: 1–2 sentences stating what the term IS — not what it does, and never implementation detail. The glossary is vocabulary, not a spec.
- **`Avoid:` line**: the synonyms considered and rejected for this concept, comma-separated. This line is the anti-synonym enforcement point — it answers the future session that reaches for a competing word.
- Group entries under subheadings only when natural clusters emerge; a flat list is fine.

## Admission rule

Project-context terms only. General programming concepts (retry, timeout, handler, cache, DTO) stay out even when the project uses them heavily — a term earns an entry only when its meaning is specific to this project's domain.

## Placement

- **Single context (most repos):** one glossary file at the repo root.
- **Multiple bounded contexts:** one glossary per context directory, plus a root map file listing each context, where its glossary lives, and how the contexts relate. Infer which context the current topic belongs to; ask when unclear.
- **Filename:** when the consuming project already keeps a domain-vocabulary file (e.g. `UBIQUITOUS-LANGUAGE.md`), use that file and apply this entry format inside it. Otherwise default to `GLOSSARY.md` at the chosen root (multi-context map file: `GLOSSARY-MAP.md`).
- **Create lazily.** No glossary exists until the first term resolves — create the file then, never speculatively.

## Update discipline

Update the glossary the moment a term resolves in discussion — never batch vocabulary capture to the session tail. A resolved term left unwritten gets relitigated next session. When a resolution changes an existing entry, refine that entry in place rather than appending a duplicate.
