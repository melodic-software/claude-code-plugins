---
description: "The scaffold seeds a fixture fleet in the run's home (a marketplace, its catalog, install records and settings) so the default marketplace resolves. Needs --scaffold --allow-tools Bash, with the real node first on PATH: a mise shim on PATH fails under the run's temporary home."
tags: ['plugins-audit']
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'The skill runs sync-run.sh with --audit (never --journal-root, --pull-source or --only-install), pastes the rendered prediction, and tells the user that applying it is /harness-ops:plugins sync, which they run themselves. It reports a zero-update prediction as a lower bound against the unrefreshed catalog, not as proof the fleet is current.'
---

Are my plugins current? Don't change anything yet.
