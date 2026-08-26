# L4 encapsulation. Leaked skills in `plugins/claude-ops`

3 violations. Two are skill-to-skill inside the plugin; one crosses a plugin boundary from
`claude-config`, which is the portability-breaking case.

**Leak kind:** private subdir (3 of 3).

## V-ops-01. `plugins/claude-config/skills/audit-pass/reference/run-state-and-resumability.md:70`

**Owning skill:** `claude-ops:lanes`. **Private surface:** `context/restart-consumer.md`.
**Severity:** highest of the three. `claude-config` and `claude-ops` are separately installable
plugins; a consumer with `claude-config` and no `claude-ops` gets a dangling pointer, and a
`claude-ops` refactor breaks a file in a different plugin's release train.

Verbatim:

```text
  defect class (`plugins/claude-ops/skills/lanes/context/restart-consumer.md`, "**age alone never
```

**Public surface element:** `/claude-ops:lanes`. The citing text is naming a defect class the lanes
skill defines, which is a behavior-and-vocabulary reference rather than a file the reader must open.

**Replacement text:**

```text
  defect class (`/claude-ops:lanes`, "**age alone never
```

If the audit-pass skill genuinely needs the restart-consumer rule as data rather than as a named
class, this becomes **Path A**: promote the rule to `docs/conventions/` (it is a cross-plugin
concern by construction) and cite it there from both plugins.

## V-ops-02. `plugins/claude-ops/skills/audit-skill-visibility/SKILL.md:103`

**Owning skill:** `claude-ops:plugins`. **Private surface:** `context/scope-semantics.md`.
Skill-to-skill within the plugin, on a T2 surface.

```text
[`skills/plugins/context/scope-semantics.md`](../plugins/context/scope-semantics.md),
```

**Public surface element:** `/claude-ops:plugins`.

**Replacement text:**

```text
`/claude-ops:plugins`,
```

Scope semantics is plugin-wide vocabulary (`plugins/claude-ops/` already carries plugin-level
directories), so if the citing skill needs the semantics themselves rather than a pointer, promote
`context/scope-semantics.md` to `plugins/claude-ops/reference/scope-semantics.md` and cite it there.

## V-ops-03. `plugins/claude-ops/skills/lanes/context/refresh.md:128`

**Owning skill:** `claude-ops:plugins`. **Private surface:** `context/sync.md`.

```text
[context/sync.md](../../plugins/context/sync.md); the lanes launch already runs
```

**Public surface element:** `/claude-ops:plugins`. The following clause ("the lanes launch already
runs") says the caller wants the behavior, not the document, which is the textbook Path B signal.

**Replacement text:**

```text
`/claude-ops:plugins`; the lanes launch already runs
```

## Cross-lane observations

- L2 (progressive disclosure): `claude-ops` carries several skills with deep `context/` trees. If L2
  splits `skills/plugins/context/`, V-ops-02 and V-ops-03 must re-resolve before wave 3 applies.
