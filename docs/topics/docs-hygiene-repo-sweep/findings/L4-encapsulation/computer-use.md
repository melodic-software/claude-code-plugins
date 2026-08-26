# L4 encapsulation. Leaked skills in `plugins/computer-use`

1 violation, skill-to-skill inside the plugin, and it is an imperative rather than a pointer.

**Owning skill:** `computer-use:diagnose` (`plugins/computer-use/skills/diagnose/`).
**Private surface reached:** `reference/failure-diagnostics.md`.
**Leak kind:** private subdir.
**Citing file:** `plugins/computer-use/skills/setup/SKILL.md:22`, a T2 surface.

## V-cu-01

Verbatim:

```text
Read [`../diagnose/reference/failure-diagnostics.md`](../diagnose/reference/failure-diagnostics.md)
```

The line opens with `Read`, so this is not a "see also": `setup` instructs the agent to load a file
out of `diagnose`'s private body at runtime. That makes the dependency load-bearing rather than
documentary. If `diagnose` renames or splits `reference/failure-diagnostics.md`, `setup` issues a
Read against a path that no longer exists, and the failure surfaces as a confusing tool error rather
than as a broken link.

**Public surface element:** `/computer-use:diagnose`. The skill exists to diagnose computer-use
failures, which is exactly what the loaded reference is for. `setup` wants the behavior, not the
document, which makes this a clean **Path B. route**.

**Replacement text:**

```text
Invoke `/computer-use:diagnose`
```

Verify the surrounding sentence after the edit: the original continues past the link, and "Invoke"
may need the following clause reworded from "for the failure table" to "to work the failure through".

## Judgment note

Do not promote `reference/failure-diagnostics.md` to a plugin-level `reference/`. The plugin ships
two skills and the diagnostics are `diagnose`'s whole product; hoisting them would leave `diagnose`
as a thin wrapper around a file its sibling also reads, which is the wrong-direction Path A the
skill's anti-pattern list warns about.

## Cross-lane observations

- None. Neither file overlaps another lane's likely edit set.
