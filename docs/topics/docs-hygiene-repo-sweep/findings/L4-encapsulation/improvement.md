# L4 encapsulation. Leaked skills in `plugins/improvement`

1 violation, from the plugin README into `improvement:find`.

**Owning skill:** `improvement:find` (`plugins/improvement/skills/find/`).
**Private surface reached:** `context/unattended.md`.
**Leak kind:** private subdir.
**Citing file:** `plugins/improvement/README.md:68`, an external consumer under the contract.

## V-imp-01

Verbatim:

```text
[skills/find/context/unattended.md](skills/find/context/unattended.md)). Iterate on the wording
```

Note the link label is the raw path with no backticks, so the leak is visible to a reader as a path
rather than as a described surface. That is the shape the contract asks external consumers to stop
writing: the README is teaching readers an address inside a private body.

**Public surface element:** `/improvement:find`. The sentence continues into an instruction about
iterating on wording, so the reader is being pointed at how the skill behaves when run unattended.

**Replacement text:**

```text
`/improvement:find` in its unattended mode). Iterate on the wording
```

## Judgment note

Check whether unattended operation is a documented flag or mode of `/improvement:find` before
applying. If it is, name it in the replacement (`/improvement:find --unattended` or the mode's real
spelling). If it is not, the replacement above is correct as written and the gap is worth one line to
the user: a README describing a mode the skill does not advertise in its own action surface is the
signal the contract's Path B calls "the caller wants behavior the skill has no public action for".
Do not file a work item for it on the strength of one cite; surface it in the reconciliation notes.

## Cross-lane observations

- L8 (write-for-humans): `plugins/improvement/README.md` is a HUMAN-audience file, and the unbackticked
  raw-path link is a readability defect independent of encapsulation. Same line, two lanes.
