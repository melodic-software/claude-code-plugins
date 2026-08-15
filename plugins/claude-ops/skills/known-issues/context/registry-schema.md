# Registry schema (`registry.json`)

The schema's source of truth is [`scripts/registry_manager.py`](../scripts/registry_manager.py):
`REQUIRED_FIELDS`, `VALID_CATEGORIES`, `VALID_STATUSES`, `validate_issue()` (URL prefix, ISO date
fields, duplicate-number detection), and `resolve_data_dir()` for the registry location
(`<registry-dir>/registry.json` — see the SKILL.md registry-location rule; defaults to
`${CLAUDE_PLUGIN_DATA}`). `scripts/registry_manager.py validate` enforces the shape; read the
constants there rather than a copy here.
