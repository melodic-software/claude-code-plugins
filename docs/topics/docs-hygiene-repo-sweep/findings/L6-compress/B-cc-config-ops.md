# L6-compress — `B-cc-config-ops`

5 COMPRESS files, all instances of finding C1.

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
| `plugins/claude-ops/README.md:316` |
| `plugins/context-budget/README.md:118` |
| `plugins/context-guard/README.md:166` |
| `plugins/guardrails/README.md:403` |
| `plugins/rate-limit-guard/README.md:156` |

## Not proposed in this group

`plugins/claude-config/skills/audit-pass/reference/terms.md` was nominated COMPRESS and overturned:
its single flavor token is a scope qualifier, matrix (d), and the file is a small-file density
artifact at exactly the 5-per-kilo-word threshold.

`plugins/claude-config/skills/audit-automation-gaps/context/gap-analysis.md` was nominated UNCERTAIN
and resolved to SKIP: both "actually" tokens carry the interrogative's point.

`plugins/claude-config/skills/audit-pass/reference/suppression.md:63` contains an `in order to` that
is **deliberately preserved**, carrying an inline `<!-- ai-slop-ignore: purposive in-order-to -->`
marker with a stated reason. It is not a candidate. Reasoning for all three in `classification.md`.
