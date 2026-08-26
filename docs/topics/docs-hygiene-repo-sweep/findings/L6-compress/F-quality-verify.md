# L6-compress — `F-quality-verify`

1 COMPRESS file, an instance of finding C1.

## Do not apply this as a markdown edit

The span below sits inside the generated block delimited by
`<!-- BEGIN GENERATED: plugin options — edit plugin.json, then run scripts/sync-plugin-options-docs.py -->`
and `<!-- END GENERATED: plugin options -->`. `scripts/sync-plugin-options-docs.py` owns the text and
CI runs its `--check` mode against drift. Apply the cut once in the generator and regenerate. The
procedure is in `README.md`, "Finding C1 remediation". The before and after pair below is given so
the wave 4 semantic-diff gate has the exact span to adjudicate.

## Cut

Flavor class: verbose form, `flavor-vs-content-matrix.md` "Flavor (safe to cut)", the
`"in order to" / "due to the fact that" verbose forms` entry. Independently backed by this repo's own
`plugins/docs-hygiene/skills/write-for-humans/SKILL.md:56`, which states: `"In order to" is "to".`

No content class is touched. The directive (`Do **not**`), the inline-code token
(`` `claude plugin uninstall` ``), the scope qualifier (`` `project`/`local` scope ``), and the
rationale that follows on the next line all survive byte-identical.

### `plugins/bugs/README.md:165`

Before:

```text
   `project`/`local` scope. Do **not** `claude plugin uninstall` in order to
```

After:

```text
   `project`/`local` scope. Do **not** `claude plugin uninstall` to
```

## Not proposed in this group

`plugins/tdd/skills/principles/reference/methodology-beck.md` was nominated COMPRESS and overturned:
all eight flavor tokens sit inside verbatim Beck and Fowler quotations. Line 14's "and perhaps
doesn't even compile" is Beck's own phrasing of the Red step.

`plugins/codebase-health/skills/audit/reference/audit-checklist.md` was nominated UNCERTAIN and
resolved to SKIP: its six tokens are matrix (c) pairs ("not just some", "not just the first",
"don't just spot-check") and matrix (d) claim-versus-reality contrasts ("actually exists",
"actually done"), which are the checklist's whole subject.

`plugins/tdd/skills/principles/reference/anti-patterns-khorikov.md:185` and
`four-pillars-khorikov.md:36` carry `in order to` and `end result` inside verbatim Khorikov
quotations; `end result` is his technical term, not a redundant pair. Reasoning in
`classification.md`.
