# L4 encapsulation. Leaked skills in `plugins/x`

1 violation, from the plugin README into `x:read`.

**Owning skill:** `x:read` (`plugins/x/skills/read/`).
**Private surface reached:** `context/failure-modes.md`.
**Leak kind:** private subdir.
**Citing file:** `plugins/x/README.md:73`, an external consumer under the contract.

## V-x-01

Verbatim:

```text
[`skills/read/context/failure-modes.md`](skills/read/context/failure-modes.md).
```

**Public surface element:** `/x:read`.

**Replacement text:**

```text
`/x:read`, which documents the failure modes and what each one means.
```

## Judgment note

`plugins/x` ships one skill, so the rip-and-paste argument is the whole case: moving
`plugins/x/skills/read/` into another repo carries every implementation detail with it, and this
README cite is the one external dependency that would not travel. Route is the fix; there is no
shared-vocabulary case for promoting a single skill's failure-mode list to a plugin-level directory
that would then have exactly one reader.

Verify the sentence after the edit. The original line ends the sentence at the link, so the
replacement needs to stand as a complete clause where the original relied on the link text.

## Cross-lane observations

- L8 (write-for-humans): `plugins/x/README.md` is a HUMAN-audience file. Same line, two lanes;
  reconciliation should give the file one owner.
