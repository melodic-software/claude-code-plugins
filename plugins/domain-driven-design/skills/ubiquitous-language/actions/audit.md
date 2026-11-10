# audit

Check a glossary against the contract, find its rejected words still in use, and propose entries to
prune. Read-only: every finding is a report line; changes go through `curate` and
`/docs-hygiene:rename-references`.

## Steps

1. Run [locate.md](locate.md) and read each glossary and the glossary index it finds.
2. Check every entry against [../context/glossary-contract.md](../context/glossary-contract.md):
   - a definition says what the concept is, in 1-2 sentences, with no implementation, behavior
     backlog, storage detail, changing number or business rule (the finding suggests where the rule
     goes: code and a test, its reason in an ADR);
   - an entity's states sit under the entity, unless a state has its own entry because people use it
     as a noun with rules of its own;
   - an `Actions:` line names a rejected verb for each chosen one;
   - the index lists each context's glossary and every listed path exists.
3. Find prune candidates, each kind its own group:
   - **Implementation:** the entry names a table, column, component, file or route rather than a
     domain concept.
   - **Too general:** a generic programming, framework or tooling word (button, component, loader),
     or an everyday word in its ordinary sense, that removes no ambiguity in this context.
   - **Unused:** a canonical term with no use in the context's code or docs.
   - **Merge:** a phrase one existing term already covers; name that term.
4. Search the scope's code, docs, copy and error messages for each `Avoid:` word and each rejected
   verb on an `Actions:` line where it names that operation on that entity (beside the entity's
   name, or in an identifier such as `cancelInvoice`; elsewhere the verb is ordinary English) and
   group the hits as `curate` step 5 does. A hit matching the entry's `Shown to users as:` wording is
   not drift.

Steps 3 and 4 count every term as the contract's
[Counting a term](../context/glossary-contract.md#counting-a-term) says.

## Output

Contract findings, then prune candidates grouped by kind, each with a one-line reason (an unused term
with its count and the counting method), then rejected-word hits by `curate` step 5's groups. Each
finding has `file:line` and the change it suggests; removals and merges go through `curate`. Close
with the counts. With no glossary: `Glossary: none` and a pointer to `seed`.
