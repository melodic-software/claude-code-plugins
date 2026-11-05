---
description: "The scaffold seeds a fixture fleet in the run's home (a marketplace, its catalog, install records and settings) so the default marketplace resolves. Needs --scaffold --allow-tools Bash, with the real node first on PATH: a mise shim on PATH fails under the run's temporary home."
tags: ['plugins-audit']
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'audit runs the same algorithm as sync but every mutating CLI call becomes a prediction: no `claude plugin install|update|uninstall|marketplace update` command is ever run, and normalize-enabled-plugins.sh is invoked with --check rather than written. The reads those calls sit beside still run. Step 1''s pre-refresh fleet-state.sh snapshot is taken (into the run''s throwaway scratch directory) so the catalog-regression check keeps its first interval, and only the `claude plugin marketplace update` beside it is replaced by a prediction. The response calls fleet-state.sh (read-only) and reports what sync/converge would do without doing it.'
---

/harness-ops:plugins-audit
