---
description: "Deprecated: this skill moved to /attribution:audit when the provenance plugin was renamed to attribution. Tells you to install the attribution plugin and re-run the audit there; does no audit work itself. Use when: 'provenance audit', '/provenance:audit' is typed out of habit."
user-invocable: true
disable-model-invocation: true
---

# provenance:audit (moved)

This skill moved to `/attribution:audit`. The `provenance` plugin was renamed to `attribution`,
and this entry is a deprecation shim that is removed in a later release.

Tell the user exactly this, then stop:

1. Install the `attribution` plugin from the marketplace that supplied this one.
2. Remove this plugin's `provenance@<marketplace>` entry from `enabledPlugins`, and rename any
   `.claude/provenance.json` to `.claude/attribution.json`.
3. Re-run the request as `/attribution:audit`, with the same arguments.

Do not run an audit, read the corpus, or edit any file from this skill.
