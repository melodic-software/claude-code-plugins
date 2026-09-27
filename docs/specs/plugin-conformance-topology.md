# Plugin alignment audit: topology

Phase 4 sketch. Name (T8) and registry home (T9) are resolved. Every path below is
proposed, nothing exists yet. No `type-inventory.md`: the one data shape is the registry row below.

## Layout

```text
docs/plugin-philosophy.md            rules (owner); cites audit-plugin-conformance by slash invocation (T7)
docs/conformance-dimensions.md                   concern registry: one row per dimension (T9)
scripts/check-skill-leaf-names.sh    extended: verb grammar + baseline (T10, T13)
scripts/skill-leaf-verbs.txt         verb list + noun exceptions (data file for the above)
scripts/list-plugin-dependencies.sh  new: candidate list for concern 5 (T13)
scripts/list-plugin-literals.sh      new: repeated literals inside one plugin, concern 6 (T13)
scripts/check-conformance-registry.sh  new: every registry row names a check that exists (T13)
scripts/*.test.sh                    one fixture test per script (T16)
.claude/skills/audit-plugin-conformance/SKILL.md      orchestrator: runs scripts, dispatches judgment, reports (T1, T14)
```

## Dependency direction

`SKILL.md` reads `docs/conformance-dimensions.md`; the registry cites philosophy sections by path and names checks. Scripts
know nothing about the skill or the registry, so CI runs them standalone. Judgment skills from other
plugins are reached by slash invocation, presence-gated. Nothing in `docs/` or `scripts/` cites a file
inside `.claude/skills/audit-plugin-conformance/`.

## Registry row

| Field | Meaning |
|---|---|
| `id` | Stable dimension id; keeps `dim-8`, `dim-9`, `dim-11`, numbers the rest after them |
| `concern` | One line, for example "one owner per value" |
| `owner` | The philosophy section or convention doc stating the rule, by path |
| `checks` | Scripts and skills implementing it, each with kind: `script`, `skill`, `judgment` |
| `ci` | Whether a CI step runs the script today |
| `scope` | `plugin` (per plugin) or `fleet` (once over the tree) |
