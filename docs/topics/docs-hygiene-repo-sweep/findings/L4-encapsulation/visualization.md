# L4 encapsulation. Leaked skills in `plugins/visualization`

1 violation, from the plugin README into `visualization:visualize`.

**Owning skill:** `visualization:visualize` (`plugins/visualization/skills/visualize/`).
**Private surface reached:** `context/decision-matrix.md`.
**Leak kind:** private subdir.
**Citing file:** `plugins/visualization/README.md:26`, an external consumer under the contract.

## V-vis-01

Verbatim:

```text
[`context/decision-matrix.md`](skills/visualize/context/decision-matrix.md).
```

The link label (`context/decision-matrix.md`) reads as if the file sat beside the README, while the
target reaches into the skill. That mismatch is worth naming on its own: a reader cannot tell from
the rendered text that the address is inside a private body, so the leak is invisible until the link
breaks.

`plugins/visualization` ships exactly one skill, which is the case where a leak looks harmless. It is
not: the contract's guarantee is that `plugins/visualization/skills/visualize/` can be ripped and
pasted into another repo whole, and this README cite is precisely the kind of external dependency
that guarantee forbids.

**Public surface element:** `/visualization:visualize`.

**Replacement text:**

```text
`/visualization:visualize`, which carries the chart-type decision matrix.
```

## Judgment note

Single-skill plugins are where the "it's only one place" tolerance shows up, and the skill's own
anti-pattern list names it: encapsulation rot accumulates one violation at a time, and each is a
binary contract break rather than a threshold. Reported.

## Cross-lane observations

- L8 (write-for-humans): `plugins/visualization/README.md` is a HUMAN-audience file, and the
  label/target mismatch is a readability defect independent of encapsulation. Same line, two lanes.
