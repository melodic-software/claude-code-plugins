# Hooks

- Mods: a hooks module follows the mod-authoring convention and ADR 0052:
  [rule](../../.claude/rules/mod-authoring.md).
- A hook unit never depends on a skill, an agent or any file of another plugin. A skill plugin may
  read what a hook unit records only through a documented path, and must fall back when that hook
  unit is off.
- A hook false-positive fix lands with a stay-quiet test that fails before the fix:
  [hook-precision](../contracts/hook-precision/README.md#the-discipline).
