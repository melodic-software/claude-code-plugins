# L6-compress — `H-knowledge-research`

6 COMPRESS files, all instances of finding C1. This group carries both line-wrap variants of the
generated sentence.

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
(`` `claude plugin uninstall` ``), the scope qualifier, and the rationale that follows all survive
byte-identical.

### Variant A (4 files)

Before, in each:

```text
   `project`/`local` scope. Do **not** `claude plugin uninstall` in order to
```

After, in each:

```text
   `project`/`local` scope. Do **not** `claude plugin uninstall` to
```

| Path and line |
|---|
| `plugins/ai-briefing/README.md:114` |
| `plugins/education/README.md:134` |
| `plugins/knowledge/README.md:147` |
| `plugins/visualization/README.md:124` |

### Variant B (2 files)

Every option these two plugins declare is `sensitive`, so the generator takes its sensitive-only
branch (`scripts/sync-plugin-options-docs.py:118` `else:`) and emits a differently-wrapped sentence
carrying `either`. This is the only branch that produces variant B, which is why exactly two files
in the corpus carry it.

Before, in each:

```text
   `claude plugin uninstall` in order to reconfigure either: uninstalling drops this
```

After, in each:

```text
   `claude plugin uninstall` to reconfigure either: uninstalling drops this
```

| Path and line |
|---|
| `plugins/dometrain/README.md:187` |
| `plugins/miro/README.md:123` |

## Not proposed in this group

`plugins/ai-briefing/skills/generate/evals/fixtures/candidate-items-sample.md` was nominated
COMPRESS by the mechanical scan and overturned: eval fixture, excluded by
`context/target-types.md` "Target validation" gate 5. Reasoning in `classification.md`.
