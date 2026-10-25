---
bump: minor
---

### Changed

- **The team layer is `docs/conventions/multi-agent.yaml`**, under the convention home the repository binds (`docs/conventions` when it binds none), validated by the new `schemas/multi-agent.schema.json`. `resolve-roles.sh` reads the old team locations, the `yaml config` block in `docs/conventions/multi-agent.md` and then `.claude/multi-agent.yaml`, only when the YAML is absent, for one release; when several exist it uses the first and names each one it ignored in `notes`. The `layers` rows and each role's `source` name the layer that supplied a value, as before.
- `/multi-agent:setup apply --layer team` writes the YAML. While the YAML is absent, the old team file the resolver still reads seeds its keys, and that file is left as it was. The skill no longer writes a `yaml config` block.
- The plugin ships `lib/resolve-convention-home.sh`, a generated copy of the shared helper.
