# prune

Remove or merge glossary entries that do not earn their place. Only entries the person accepts are
removed or merged; a request to prune accepts nothing by itself.

## Steps

1. Run [locate.md](locate.md) and read each glossary and the glossary index it finds. With no
   glossary: `Glossary: none` and a pointer to `seed`.
2. Find the candidates as [audit.md](audit.md#steps) step 3 does, in its groups and order
   (Implementation, Too general, Unused, Merge), counting each term as the contract's
   [Counting a term](../context/glossary-contract.md#counting-a-term) says. Candidates named in the
   request or by an earlier `audit` run join their group.
3. Present the candidates one group at a time, each with its reason and, for an unused term, its
   count. Write only the entries the person said yes to; a group without a yes stays as it is.
   Unattended, or with no answer, report the candidates and write nothing.
4. Re-read the target file immediately before editing it: another turn or agent may have changed it.
   A merge keeps the covering term's entry, removes the other and records the removed phrase on the
   covering entry's `Avoid:` line.
5. Report every reference that still names a removed term, by file and line, for the same reviewed
   change: its uses inside other entries, bold mentions and plain words alike, the glossary index
   (which counting skips), and docs.

## Output

The entries removed or merged with the counts their question gave and, for each, where its meaning
went (an `Avoid:` word on the covering term, moved to code or a doc, or dropped); two counts of
entries: accepted (the entries the person said yes to) and removed (the entries in the glossary file
before the edit and absent after it, read from the file; a merge counts the entry it removed),
naming any entry in one set and not the other; then the surviving references to removed terms. With
nothing accepted, the candidates by group and `Removed: 0`.
