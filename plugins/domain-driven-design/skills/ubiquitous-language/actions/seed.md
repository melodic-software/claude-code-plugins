# seed

Propose a first glossary for a scope that has none, from the words the code and docs already use.
A person accepts or rejects every term; only accepted terms are written. Growing the glossary one
resolved term at a time through `curate` stays the default; `seed` is for a brownfield repository
where several names for one concept already exist and nobody has written them down.

## Steps

1. Run [locate.md](locate.md). When a glossary already covers the scope, stop and offer `audit` or
   `curate` instead.
2. Collect candidates from the scope: type and module names, enum values, table and route names,
   headings and repeated nouns in its docs, and words in user-facing copy and error messages. Keep
   project-specific domain concepts; drop framework, tooling and generic programming words.
3. Group names that look like one concept (`Order`, `Purchase`, `Checkout` for the same record),
   with the count and a `file:line` example of each. Group an entity's states under the entity.
4. Present the candidates as one numbered list, each with a proposed canonical term (the name the
   code uses most, unless the docs and copy agree on another), a one-line definition drawn from how
   the code uses it, and the other names as proposed `Avoid:` words. Mark the definition as inferred
   from the code.
5. The person accepts, edits or rejects each item; an accept-all reply accepts the list as shown.
   Unattended, or with no answer, write nothing and report the list.
6. Write only accepted entries, in the contract's fallback shape at the location the ladder proposes
   once the person has confirmed it. Then run `curate` step 5 for the accepted `Avoid:` words.

## Output

The accepted entries and the file written, the rejected candidates, and the rename and copy hits
from `curate` step 5.
