# L6-compress — `C-vcs-repo`

4 COMPRESS files, all instances of finding C1.

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
| `plugins/disk-hygiene/README.md:361` |
| `plugins/github/README.md:111` |
| `plugins/repo-hygiene/README.md:127` |
| `plugins/source-control/README.md:359` |

## Not proposed in this group

`.claude/source-control.md` (group `M-repo-root`, listed here because it is the same subject matter)
was nominated UNCERTAIN and resolved to SKIP: both "actually" tokens contrast a documented list
against what the merge gate runs, matrix (d). Reasoning in `classification.md`.
