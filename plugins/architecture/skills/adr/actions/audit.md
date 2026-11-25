# audit

List the records the code, a later decision or the admission test no longer backs. Read-only:
writes, deletes, moves and commits nothing; removing a candidate is [`prune`](prune.md)'s. Done when
`git status --porcelain` is exactly what it was before the invocation.

## Steps

1. Discover the convention ([record Step 1](record.md#step-1-discover-the-convention)). With none,
   report the rungs searched and stop. Skip records in the archive folder and records whose status
   already retires them. Done when the records to check are listed.
2. Check each record against the code, its history and the
   [admission test](record.md#admission-test-advisory), done when every listed record has a verdict:
   - **Gone**: what it decided (a library, service, folder, setting or pattern) no longer exists in
     the code. Evidence: the search that found nothing, and the commit that removed it.
   - **Contradicted**: a later commit or record decides otherwise. Evidence: the commit, or the
     record's `file:line`.
   - **Fails admission**: one of the test's three parts fails (name it), or the decision is still
     provisional on a prototype that has not run. Evidence: the record's `file:line`.
3. Run the [citation sweep](record.md#step-3-retire-the-record-the-decision-replaces) for each
   retire candidate; the new record is a Contradicted candidate's later record, and with none the
   proposal is drop. Done when every candidate has its hits listed, or none.
4. Report retire candidates grouped by those reasons, each with identifier, title, evidence and its
   citation hits, then the count of records still backed. Done when the report is delivered.

## Several repositories

With no target form, the audit covers this repository, exactly as above. A target form resolves,
counts and fans out the repositories as target-scope.md says, and steps 1 to 3 run once per
repository with its root anchored, reading it at `origin/HEAD` as target-scope.md "Resolving
repositories" says: each walks its own ADR ladder from its root and sweeps its own citations with
`git -C <root> grep -n <pattern> origin/HEAD`. Every candidate carries its repository
(`owner/name`), and the report merges them as target-scope.md "Merging findings" says.

The report adds a fourth group, **Recorded in several repositories**: one decision held as a record
in two or more repositories, one row listing each. Its proposal keeps one record, in the repository
the instructions name for cross-repository decisions (an `AGENTS.md`, `CLAUDE.md` or ADR
convention of a repository in scope), and points the others at it. With no repository named for
that, the row asks which one keeps it.
