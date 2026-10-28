# Checking the mechanics quotes

Worked detail for the migrate skill's "Check the mechanics quotes first" step.

Where a shim, a nested `AGENTS.md` or a `.claude/rules/` file loads is priced by the surface table in
[`../../../context/verified-mechanics.md`](../../../context/verified-mechanics.md), and each
*(doc MS-<n>)* cell there rests on one sentence of a live docs page. The first command of every
run, whichever argument it has, checks those sentences:

```bash
"<plugin-root>/scripts/quote-check.sh"
```

It takes no arguments and fetches only the pages `<plugin-root>/context/mechanics-sources.tsv`
lists. It prints one line per record: `verified <id>`; `drift <id> <url>`, with the stored and
fetched sentences on the next two lines; or `unverified <id> as of <date>` when the page could not
be read fresh. It exits 0 whatever the results, so a run with no network still completes. Its grant
names the script with no `*`, and a Bash rule with no `*` matches one exact command (see
<https://code.claude.com/docs/en/permissions#wildcard-patterns>, as of 2026-10-28; recheck when that
section changes how such a rule matches).

A proposed move relies on the records its destination's row of the surface table cites.

- **Drift goes first.** At the top of the output, list each `drift` result: the record id, its
  section URL, the stored wording and the fetched one. A move that relies on a drifted record shows
  both wordings and the unverified label below, and names the wording it is planned on.
- **Quote the deciding sentence** of each record a move relies on, from the record's `quote`
  column, beside that move in the plan.
- **Label what was not read.** A move that relies on an `unverified` or a drifted record is
  labeled "unverified as of <date>", in the plan and at the apply gate. The date is the one the
  `unverified` line printed, or for a drifted record its `as_of` in the list.
