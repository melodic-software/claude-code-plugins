# L4 encapsulation. Leaked skills in `plugins/dometrain`

1 violation, from the plugin README into `dometrain:sync`.

**Owning skill:** `dometrain:sync` (`plugins/dometrain/skills/sync/`).
**Private surface reached:** `context/update.md`.
**Leak kind:** private subdir.
**Citing file:** `plugins/dometrain/README.md:132`, an external consumer under the contract.

## V-dom-01

Verbatim:

```text
[`skills/sync/context/update.md`](skills/sync/context/update.md) for the full integration
```

**Public surface element:** `/dometrain:sync`.

**Replacement text:**

```text
`/dometrain:sync` for the full integration
```

## Judgment note. Route, not promote

The integration procedure is `sync`'s product. Nothing outside the plugin consumes it, and the plugin
ships only three skills (`grounding`, `setup`, `sync`), so there is no shared-vocabulary case for
promoting it to a plugin-level directory. The sweep's standing rule prefers the in-place fix at this
multiplicity, and route is the in-place fix.

Verify the sentence after the edit: the README line runs on past the link ("for the full
integration ..."), so the replacement must leave a grammatical sentence, not a bare slash command
followed by a dangling clause.

## Cross-lane observations

- L8 (write-for-humans): `plugins/dometrain/README.md` is a HUMAN-audience file, so the sentence
  after this edit should read as prose to a human, not as an agent instruction. The L8 editor and
  this lane touch the same line; reconciliation should give the file one owner.
