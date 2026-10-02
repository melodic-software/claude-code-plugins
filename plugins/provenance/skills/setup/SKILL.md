---
description: "Deprecated: this skill moved to /attribution:setup when the provenance plugin was renamed to attribution. Tells you to install the attribution plugin and re-run setup there; writes no config itself. Use when '/provenance:setup' or 'set up provenance' is typed out of habit."
argument-hint: "[check]"
user-invocable: true
disable-model-invocation: true
---

# provenance:setup (moved)

This skill moved to `/attribution:setup`. The `provenance` plugin was renamed to `attribution`,
and this entry is a deprecation shim that is removed in a later release.

The only action is `check`, and whatever arguments arrive, it behaves the same. The shim is
check-only: it owns no config artifact, and the user makes the migration edits it names.

Tell the user exactly this, then stop:

1. Install the `attribution` plugin from the marketplace that supplied this one.
2. Remove this plugin's `provenance@<marketplace>` entry from `enabledPlugins`, and rename any
   `provenance.json` or `provenance.local.json` (in the repo's `.claude/` or in `~/.claude/`) to
   its `attribution` name.
3. Re-run the request as `/attribution:setup`, with the same arguments.

Done when those three steps are relayed and nothing else ran. Do not read or write any config
file from this skill.
