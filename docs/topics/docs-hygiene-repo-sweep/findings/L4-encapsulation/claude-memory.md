# L4 encapsulation. Leaked skills in `plugins/claude-memory`

1 violation, skill-to-skill inside the plugin.

**Owning skill:** `claude-memory:stateless` (`plugins/claude-memory/skills/stateless/`).
**Private surface reached:** `context/status.md`.
**Leak kind:** private subdir.
**Citing file:** `plugins/claude-memory/skills/audit/reference/criteria.md:95`.

## V-cm-01

Verbatim:

```text
[`skills/stateless/context/status.md`](../../stateless/context/status.md), "Resolve the effective
```

The cite is doubly bound: it names a private file and then a heading string inside it ("Resolve the
effective ..."), so an author who renames either the file or the heading breaks it. `claude-memory`
ships exactly two skills, and this line makes `audit`'s criteria depend on `stateless`'s internal
layout.

**Public surface element:** `/claude-memory:stateless status`. That action is documented in the
skill's own description ("Actions: status (default, memory + settings across all scopes), disable
..., purge ..."), and resolving the effective auto-memory state across scopes is precisely what it
does.

**Replacement text:**

```text
`/claude-memory:stateless status`, which resolves the effective
```

## Judgment note. Route, not promote

This is a behavior dependency, not a data one: the audit criteria want the effective-state resolution
performed, and `stateless status` performs it. Promoting `context/status.md` to a plugin-level
`reference/` would hoist a procedure out of the skill that runs it, which is the wrong-direction
Path A the skill's own anti-pattern list warns about.

## Cross-lane observations

- L2 (progressive disclosure): `plugins/claude-memory/skills/audit/reference/criteria.md` is a long
  criteria catalog and a plausible split candidate. If L2 splits it, V-cm-01 must re-resolve to the
  post-split file before wave 3 applies the edit.
