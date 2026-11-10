# lookup

The one public read action. Return the project's domain terms so the caller names things in them.
Read-only: never edits the glossary, even when an entry looks wrong (report it; `curate` changes it).

## Input

Optional terms or a topic, and the scope the caller works in. With no term, return every entry that
covers the scope.

## Steps

1. Run [locate.md](locate.md) for the scope.
2. Read each glossary it found with the Read tool (and the glossary index when terms may span
   contexts). Read the whole file; entries are short.
3. For each requested term, or for every entry when none was requested, take the canonical term, its
   definition, its states, its `Avoid:` list and its `Shown to users as:` line. A requested word that
   appears only on an `Avoid:` line resolves to the entry that rejected it.

## Output

```text
Glossary: <path | none>
- Loan: one tool in a member's hands for a fixed period. Avoid: checkout, rental, booking
- Refund: ... States: Pending, then Issued or Failed. Shown to users as: refund
```

Then one line for the caller: use the canonical terms in names, tests, prose and messages, and never
an `Avoid:` word, even when the request itself uses it. A word the request uses that the glossary
rejects is named, with the term that replaces it.

With no glossary: `Glossary: none` and nothing else; a missing glossary is not an error and asks
nothing. A term the glossary does not hold is reported as absent; `lookup` never invents a definition.
