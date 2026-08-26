# L4 encapsulation. Leaked skills in `plugins/code-tidying`

1 violation, and it crosses a plugin boundary.

**Owning skill:** `code-tidying:tidy` (`plugins/code-tidying/skills/tidy/`).
**Private surface reached:** `reference/tidyings.md`.
**Leak kind:** private subdir.
**Citing file:** `plugins/claude-config/skills/audit-instructions/reference/criteria.md:392`.

## V-ct-01

Verbatim:

```text
     `plugins/code-tidying/skills/tidy/reference/tidyings.md`; in a standalone install the shape,
```

`claude-config` and `code-tidying` are separately installable plugins. The clause that follows the
cite ("in a standalone install the shape, ...") shows the author already knew the target might not be
present, and handled it with prose rather than by addressing a public surface. A `code-tidying`
refactor of `reference/tidyings.md` breaks a criteria file in a different plugin's release train,
with nothing failing.

**Public surface element:** `/code-tidying:tidy`.

**Replacement text:**

```text
     `/code-tidying:tidy`, which owns the tidying catalog; in a standalone install the shape,
```

## Judgment note. Route, with a promote option

Route is sufficient for the single cite. The wider option, recorded because the reconciliation pass
may prefer it: the tidying catalog and `claude-config:audit-instructions`'s criteria catalog are two
halves of one repo-level vocabulary for "what counts as a defect in a text surface". If the
reconciliation pass takes up the repo-level instruction-audit catalog recorded in
`claude-config.md`'s judgment note, this cite folds into that move instead.

Do not vendor a copy of the tidyings list into `claude-config`. Two catalogs drift, and the drift is
exactly what the citing sentence is trying to guard against.

## Cross-lane observations

- L3 (SSOT): if `claude-config:audit-instructions` restates any part of the tidyings list rather than
  citing it, that is a duplication finding for L3 and resolves with the same edit.
