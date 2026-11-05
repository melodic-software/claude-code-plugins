---
description: "The scaffold seeds a fixture fleet in the run's home (a marketplace, its catalog, install records and settings) so the default marketplace resolves. Needs --scaffold --allow-tools Bash, with the real node first on PATH: a mise shim on PATH fails under the run's temporary home."
tags: ['plugins-audit']
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'The report''s Divergences line collapses the 29 actionable (version-behind) entries into one bulk count and names `/harness-ops:plugins converge` as the fix — it does NOT list all 29 individually (at most one sub-line per project path, each naming that path''s record count and up to 3 ids, then `+K more` when more ids remain), and it does NOT count the 2 same-version multi-scope installs as actionable (versionsMatch: true is benign). The one delisted_settings_only plugin id gets its own per-row detail line under Action needed as a genuine conflict, distinct from the bulk divergence count.'
---

/harness-ops:plugins-audit — I have 29 plugins with an actionable version divergence between project and user scope, plus 2 more that are multi-scope but pinned to the identical version, and one plugin id that fleet-state.sh reports under delisted_settings_only (true in enabledPlugins, no install record, and no matching catalog entry).
