# L4 encapsulation. Leaked skills in `plugins/overengineering`

3 violations, both skills leaked into from plugin-level surfaces in the same plugin.

**Leak kind:** private subdir (3 of 3).

## V-over-01, V-over-02. `plugins/overengineering/context/product-code-lane.md` reaches into `audit`

**Owning skill:** `overengineering:audit`. **Private surface:** `context/surface-walk.md`.
The citing file is a plugin-level context doc, outside every skill directory, so it is an external
consumer under the contract.

| # | `path:line` | Verbatim |
|---|---|---|
| V-over-01 | `plugins/overengineering/context/product-code-lane.md:38` | ``([`../skills/audit/context/surface-walk.md`](../skills/audit/context/surface-walk.md),`` |
| V-over-02 | `plugins/overengineering/context/product-code-lane.md:189` | ``The enforcement lane's preflight ([`../skills/audit/context/surface-walk.md`](../skills/audit/context/surface-walk.md),`` |

**Public surface element:** `/overengineering:audit`. Both cites describe a preflight the audit skill
performs, which is behavior.

**Replacement text, V-over-01:**

```text
(`/overengineering:audit`,
```

**Replacement text, V-over-02:**

```text
The enforcement lane's preflight (`/overengineering:audit`,
```

The surface-walk loop is also referenced from `docs/adr/0017` as historical evidence for a shipped
decision. That ADR cite is legal under the meta-prose filter (a decision record naming what it
weighed) and is not part of this finding.

## V-over-03. `plugins/overengineering/README.md:147`

**Owning skill:** `overengineering:delta`. **Private surface:** `context/recurring-wiring.md`.
A plugin README is an external consumer: it is not carried when the skill directory is ripped and
pasted, and READMEs are named explicitly in the contract.

```text
[`skills/delta/context/recurring-wiring.md`](skills/delta/context/recurring-wiring.md).
```

**Public surface element:** `/overengineering:delta`.

**Replacement text:**

```text
`/overengineering:delta`, which owns the recurring wiring.
```

## Cross-lane observations

- L1 (derivability): `plugins/overengineering/context/product-code-lane.md` overlaps
  `docs/adr/0017-ship-the-product-code-lane-as-its-own-skill.md` in subject. If L1 converts either to
  a pointer, V-over-01 and V-over-02 move or vanish. Re-resolve before applying.
