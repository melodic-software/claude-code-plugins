# L6-compress — `J-toolchain-platform`

11 COMPRESS files, all instances of finding C1. This is the largest single-group share of the
finding.

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
| `plugins/actionlint/README.md:109` |
| `plugins/bash-format/README.md:131` |
| `plugins/biome-format/README.md:117` |
| `plugins/desktop-notification/README.md:126` |
| `plugins/eol-normalizer/README.md:108` |
| `plugins/go-format/README.md:126` |
| `plugins/instruction-placement/README.md:169` |
| `plugins/machine-health/README.md:116` |
| `plugins/powershell-format/README.md:145` |
| `plugins/ruff-format/README.md:126` |
| `plugins/skill-quality/README.md:151` |

## Not proposed in this group

`plugins/plugin-quality/README.md`, `plugins/plugin-quality/skills/audit/references/recurring-concerns.md`,
and `plugins/plugin-quality/skills/audit/references/component-types/hook.md` were all nominated
UNCERTAIN by the mechanical scan and resolved to SKIP. Their tokens are matrix (c) contrastive pairs
("not just one", "or you just want to know" set against "something felt off") and matrix (d)
claim-versus-reality qualifiers ("does it resolve enablement the way Claude Code actually does").
Reasoning in `classification.md`.
