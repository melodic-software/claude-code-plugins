# prune

Retire the records that no longer earn their place, only those the person accepts. Takes the same
target forms as `audit`.

## Steps

1. Run the [Audit](../SKILL.md#audit) steps 1 to 3, and its
   [Several repositories](../SKILL.md#several-repositories) section for a target form. Writes
   nothing yet. With no candidates, report the count of records still backed and stop. Done when
   every candidate has its verdict, evidence and citation hits.
2. Report the resolved `adr_retirement` and its layer, and what it will do to each retired file.
3. Present the candidates one group at a time, in the audit's order (Gone, Contradicted, Fails
   admission, then Recorded in several repositories), each with identifier, title, evidence and its
   citation hits with their proposals. Ask which records in the group to retire; accept only
   records the person names or accepts one by one, never a blanket "all" for a group they have not
   seen. A record not accepted stays as it is. Done when every group has an answer.
4. For each accepted Contradicted candidate whose later record reverses only part of it, apply
   [Step 3](../SKILL.md#step-3-retire-the-record-the-decision-replaces)'s **Partial reversal** rule
   in place of ordinary retirement: the file stays whatever `adr_retirement` says, it gets only the
   superseded-in-part status naming the part, and only the citations of the reversed part are
   edited. Done when each such record carries that status and those citation edits.
5. For every other accepted record, run
   [Step 3](../SKILL.md#step-3-retire-the-record-the-decision-replaces) items 2 and 3: the
   acceptance is item 1's yes; the retirement follows `adr_retirement`, a `supersede` with no new
   record uses the convention's word for a withdrawn record, the citation sweep's proposals are
   edited as listed (a Contradicted candidate's later record is the record citations point at,
   otherwise drop), and with `delete` the git-history pointer line is proposed once for the ADR
   folder. Done when every accepted retirement and its citation edits are on disk.
6. Report what was retired or marked superseded in part, how, each file whose citations were
   edited, and the records left standing. Done when `git status --porcelain` shows only those
   changes and the pointer line's file if it was written.

With several repositories, a retirement runs in one repository at a time, as that section says.
