# audit

Check a glossary against the contract and find its rejected words still in use. Read-only: every
finding is a report line; changes go through `curate` and `/docs-hygiene:rename-references`.

## Steps

1. Run [locate.md](locate.md) and read each glossary and the glossary index it finds.
2. Check every entry against [../context/glossary-contract.md](../context/glossary-contract.md):
   - one entry per concept per context, no duplicate or near-duplicate terms;
   - a definition says what the concept is, in 1-2 sentences, with no implementation, behavior
     backlog, storage detail or changing number;
   - an entity's states sit under the entity, unless a state has its own entry because people use it
     as a noun with rules of its own;
   - generic programming, framework or tooling words are out;
   - the index lists each context's glossary and every listed path exists.
3. Search the scope's code, docs, copy and error messages for each `Avoid:` word (whole words,
   case-insensitive) and group the hits as `curate` step 5 does: code and docs names, then
   user-facing copy and error messages. A hit matching the entry's `Shown to users as:` wording is
   not drift.

## Output

Findings grouped as contract, code and docs names, copy and error messages, each with `file:line`
and the change it suggests, then the counts. With no glossary: `Glossary: none` and a pointer to
`seed`.
