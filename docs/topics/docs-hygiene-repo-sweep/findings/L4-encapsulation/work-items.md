# L4 encapsulation. Leaked skills in `plugins/work-items`

8 violations, all into `work-items:track`, all from plugin-level reference docs in the same plugin.
`work-items/track` is the second-most-leaked skill in the repo.

The pattern is uniform: three plugin-shared reference docs
(`reference/dogfood-filing.md`, `reference/issue-conventions.md`, `reference/label-taxonomy.md`) cite
`../skills/track/actions/<verb>.md` to pin a rule to the action document that implements it. Those
action files are `track`'s private body. `track` documents its actions publicly in its SKILL.md
action table, which is exactly the surface these cites should name.

**Owning skill:** `work-items:track` (`plugins/work-items/skills/track/`).
**Private surface reached:** `actions/add.md`, `actions/done.md`, `actions/due.md`.
**Leak kind:** private subdir (8 of 8).
**Public surface element:** the documented actions of `/work-items:track`. `add`, `done`, and `due`
are all named in the skill's own action table and in its `argument-hint`, so `/work-items:track add`,
`/work-items:track done`, and `/work-items:track due` are public, stable addresses for exactly the
content these lines want to point at. This is a clean **Path B. route**; no promotion is needed and
no public action is missing.

## Violations

### V-wi-01. `plugins/work-items/reference/dogfood-filing.md:32`

```text
   the same read `track add` performs ([`../skills/track/actions/add.md`](../skills/track/actions/add.md)
```

**Replacement text:**

```text
   the same read `track add` performs (`/work-items:track add`
```

### V-wi-02. `plugins/work-items/reference/dogfood-filing.md:50`

```text
   the argv-safe `create-item` write ([`../skills/track/actions/add.md`](../skills/track/actions/add.md)
```

**Replacement text:**

```text
   the argv-safe `create-item` write (`/work-items:track add`
```

### V-wi-03. `plugins/work-items/reference/dogfood-filing.md:60`

```text
   ([`../skills/track/actions/add.md`](../skills/track/actions/add.md) "Build labels list"): on the
```

**Replacement text:**

```text
   (`/work-items:track add`, "Build labels list"): on the
```

### V-wi-04. `plugins/work-items/reference/dogfood-filing.md:83`

```text
creating it ([`../skills/track/actions/add.md`](../skills/track/actions/add.md) "Authorization
```

**Replacement text:**

```text
creating it (`/work-items:track add`, "Authorization
```

### V-wi-05. `plugins/work-items/reference/issue-conventions.md:31`

```text
autonomous-eligible items. See [`../skills/track/actions/add.md`](../skills/track/actions/add.md)
```

**Replacement text:**

```text
autonomous-eligible items. See `/work-items:track add`
```

### V-wi-06. `plugins/work-items/reference/issue-conventions.md:37`

```text
`type:` label otherwise) — see [`../skills/track/actions/add.md`](../skills/track/actions/add.md)
```

**Replacement text:**

```text
`type:` label otherwise), see `/work-items:track add`
```

### V-wi-07. `plugins/work-items/reference/issue-conventions.md:44`

```text
`done` action's close discipline: [`../skills/track/actions/done.md`](../skills/track/actions/done.md).
```

**Replacement text:**

```text
`done` action's close discipline: `/work-items:track done`.
```

### V-wi-08. `plugins/work-items/reference/label-taxonomy.md:90`

```text
  [`../skills/track/actions/due.md`](../skills/track/actions/due.md) and the setup
```

**Replacement text:**

```text
  `/work-items:track due` and the setup
```

## Note on the em dash in V-wi-06

The verbatim line carries an em dash. The replacement above removes it, which brings the line into
line with `plugins/ai-slop/skills/audit/reference/rewrite-guide.md`. Flag to the reconciliation pass
so this edit is not counted twice against the L5/L6 in-file prose lane.

## Cross-lane observations

- L1 (derivability): `plugins/work-items/reference/dogfood-filing.md` is a narrative of one filing
  session. If L1 deletes or converts it, V-wi-01..04 are mooted. Re-check before applying.
