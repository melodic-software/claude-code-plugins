# L4 encapsulation. Leaked skills in `plugins/bugs`

1 violation, skill-to-skill inside the plugin.

**Owning skill:** `bugs:write` (`plugins/bugs/skills/write/`).
**Private surface reached:** `context/template.md`.
**Leak kind:** private subdir.
**Citing file:** `plugins/bugs/skills/scan/context/findings-report.md:29`.

## V-bugs-01

Verbatim:

```text
[`${CLAUDE_PLUGIN_ROOT}/skills/write/context/template.md`](../../write/context/template.md) for the
```

`bugs:scan` and `bugs:write` are deliberately paired: `scan`'s own description says a bug you already
observed goes to `bugs:write`, and `write` emits the 5-field report shape. That pairing is correct.
The wiring is not: `scan` currently depends on the filename `write` happens to use for its template.

**Public surface element:** `/bugs:write`. Its documented output is the structured 5-field report
(title, steps to reproduce, expected vs actual, severity with justification, suggested fix location),
which is exactly what `scan` wants.

**Replacement text:**

```text
`/bugs:write`, whose 5-field report shape this reuses, for the
```

## Judgment note. Route, not promote

The report template is `bugs:write`'s product, not shared vocabulary: no third surface consumes it.
Promoting it to `plugins/bugs/reference/` would create a plugin-level file with exactly two readers,
which the sweep's standing rule ("dedup prefers rule-of-one") argues against. Route is the right
remedy.

The one condition that flips this: if `scan --track` must emit a file byte-identical to what
`/bugs:write` emits, and the two skills currently keep separate copies of the field list, then the
duplication is real and the promotion target is `plugins/bugs/reference/report-shape.md`. Verify
before applying.

## Cross-lane observations

- L3 (SSOT): check whether `scan/context/findings-report.md` restates the 5-field list rather than
  pointing at it. If it does, this is a duplication finding as well as an encapsulation one, and both
  resolve with the same edit.
