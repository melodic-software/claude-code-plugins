# architecture conventions

```yaml
architecture_dir: docs/architecture
landscape_dialect: mermaid
```

## Boundary rules

- A plugin's code never loads a file from a sibling plugin: no file under `plugins/<a>/` references a path under `plugins/<b>/`, a != b. Outside the rule: a generated shared copy registered in `scripts/shared-copies.txt`, which is a file inside the plugin, and a Markdown path citation, which [ADR 0018](../../adr/0018-treat-the-plugin-as-the-encapsulation-boundary-for-skill-citation.md) governs. Evidence: docs/plugin-philosophy.md:100. Accepted 2026-11-16. Enforced by: `scripts/check-plugin-imports.sh`.
