# audit

Check a glossary against the contract, find its rejected words still in use, and propose entries to
prune. Read-only: every finding is a report line; changes go through `curate` and
`/docs-hygiene:rename-references`.

## Steps

1. Run [locate.md](locate.md) and read each glossary and the glossary index it finds.
2. Check every entry against [../context/glossary-contract.md](../context/glossary-contract.md):
   - a definition says what the concept is, in 1-2 sentences, with no implementation, behavior
     backlog, storage detail, changing number or business rule (the finding suggests where the cut
     sentence goes: a rule to code and a test, its reason to an ADR, operating detail to user docs
     or command help);
   - an entity's states sit under the entity, unless a state has its own entry because people use it
     as a noun with rules of its own;
   - an `Actions:` line names a rejected verb for each chosen one;
   - the index lists each context's glossary and every listed path exists.
3. Find prune candidates, each kind its own group:
   - **Implementation:** the entry names a table, column, component, file, route, or a constant or
     setting that lives in code, rather than a domain concept.
   - **Too general:** a generic programming, framework or tooling word (button, component, loader),
     or an everyday word in its ordinary sense, that removes no ambiguity in this context.
   - **Unused:** a canonical term with no use in the context's code or docs.
   - **Merge:** a phrase one existing term already covers; name that term.
4. Search the scope's code, docs, copy and error messages for each `Avoid:` word and each rejected
   verb on an `Actions:` line where it names that operation on that entity (beside the entity's
   name, or in an identifier such as `cancelInvoice`; elsewhere the verb is ordinary English) and
   group the hits as `curate` step 5 does. A hit matching the entry's `Shown to users as:` wording is
   not drift. A hit where the `Avoid:` word names a concept of its own, not this one, is a candidate
   entry, not drift; it goes to `curate`.
5. Group the scope's code names that look like an existing term's concept, as `seed` step 3 does,
   and report each one that is neither the term nor one of its `Avoid:` words, with its count and a
   `file:line`. Each finding proposes the name as a new `Avoid:` word through `curate`, or, when the
   name carries a meaning of its own (its own fields or behavior), as a candidate entry. Two copies
   of the same logic are not a glossary finding: duplicated code goes to
   `/code-metrics:audit-duplication`.

Steps 3 to 5 count every term as the contract's
[Counting a term](../context/glossary-contract.md#counting-a-term) says.

## Output

Contract findings, then prune candidates grouped by kind, each with a one-line reason (an unused term
with its count and the counting method), then rejected-word hits by `curate` step 5's groups, then
step 4's candidate entries, then step 5's unrecorded names, each with its proposed `Avoid:` word or
as a candidate entry. Each
finding has `file:line` and the change it suggests; removals, merges and new `Avoid:` words go
through `curate`. Close with the counts. With no glossary: `Glossary: none` and a pointer to `seed`.
