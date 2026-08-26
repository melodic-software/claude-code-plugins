# L4 encapsulation. Leaked skills in `plugins/autonomy`

1 violation. It is the only schema-file leak in the corpus, and it crosses a plugin boundary.

**Owning skill:** `autonomy:setup` (`plugins/autonomy/skills/setup/`).
**Private surface reached:** `schemas/guardrails-security-binding.schema.json`.
**Leak kind:** schema file. The contract puts `*.schema.json` at any depth on the private side with
no carve-out, and names the remedy directly: route via `/skill-name <action>`, or vendor the schema
to a shared tooling location the consumer repo owns.
**Citing file:** `plugins/source-control/skills/babysit-loop/reference/promotion-evidence-resolution.md:8`.

## V-auto-01

Verbatim:

```text
([`guardrails-security-binding.schema.json`](../../../../autonomy/skills/setup/schemas/guardrails-security-binding.schema.json)
```

The relative path climbs four levels out of `source-control` and back down into `autonomy`, which is
the clearest possible signal of a reach across a boundary the layout was not built to support. The
two plugins are separately installable, so a consumer with `source-control` and no `autonomy` gets a
dangling link, and an `autonomy` schema refactor breaks a file in another plugin's release train.

**Public surface element:** `/autonomy:setup`. The binding the citing file needs is what the setup
skill writes and validates; the schema's location is implementation detail by the contract's own
words ("Schema location is implementation detail").

**Replacement text:**

```text
(the guardrails-security binding `/autonomy:setup` writes and validates
```

**If `babysit-loop` needs the schema as data, not as a named contract,** this becomes **Path A**:
promote the binding schema to a repo-owned tooling location (for example
`docs/conventions/guardrails-security-binding/` alongside a copy of the schema, or a top-level
`schemas/` directory) that both plugins cite. Do not vendor a second copy inside `source-control`:
two schemas drift, and the drift is silent.

## Cross-lane observations

- None. `plugins/autonomy` ships one skill and no plugin-level docs, so nothing in this plugin
  overlaps another lane's edit set.
