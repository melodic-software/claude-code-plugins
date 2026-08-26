# L6-compress — `D-work-planning`

2 COMPRESS files, both instances of finding C1.

## Do not apply these as markdown edits

Every span below sits inside the generated block delimited by
`<!-- BEGIN GENERATED: plugin options — edit plugin.json, then run scripts/sync-plugin-options-docs.py -->`
and `<!-- END GENERATED: plugin options -->`. `scripts/sync-plugin-options-docs.py` owns the text and
CI runs its `--check` mode against drift. Apply the cut once in the generator and regenerate. The
procedure is in `README.md`, "Finding C1 remediation". The before and after pairs below are given so
the wave 4 semantic-diff gate has the exact spans to adjudicate.

## Cut

Flavor class: verbose form, `flavor-vs-content-matrix.md` "Flavor (safe to cut)", the
`"in order to" / "due to the fact that" verbose forms` entry. Independently backed by this repo's own
`plugins/docs-hygiene/skills/write-for-humans/SKILL.md:56`, which states: `"In order to" is "to".`

No content class is touched. The directive (`Do **not**`), the inline-code token
(`` `claude plugin uninstall` ``), the scope qualifier (`` `project`/`local` scope ``), and the
rationale that follows on the next line all survive byte-identical.

Every file in this group carries the same variant. Before, in each:

```text
   `project`/`local` scope. Do **not** `claude plugin uninstall` in order to
```

After, in each:

```text
   `project`/`local` scope. Do **not** `claude plugin uninstall` to
```

| Path and line |
|---|
| `plugins/planning/README.md:100` |
| `plugins/work-items/README.md:209` |

## Not proposed in this group

Nothing else in `D-work-planning` cleared the matrix. All 109 files in the group scored below the
flavor-token density floor or carried only load-bearing tokens.
