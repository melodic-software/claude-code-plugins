---
description: 'Present-path case: the playground-stub stand-in lists a playground skill whose description matches the upstream one, so the skill can route to playground:playground. Narration gap: with no Bash, Step 1 cannot run claude plugin list, and no fixture provides a playground@claude-plugins-official install record, so presence-from-install-record is not expected to pass here.'
tags: ['use', 'narration']
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Confirms the upstream playground plugin is installed by its claude-plugins-official install record, then invokes the upstream skill via the Skill tool using the namespaced `playground:playground` form with the balancing brief, and does not generate any playground HTML itself.'
---

/playgrounds:use help me balance the 'Inferno' hero's deck
