---
tags: ['use', 'narration']
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Confirms the upstream playground plugin is installed by its claude-plugins-official install record, then invokes the upstream skill via the Skill tool using the namespaced `playground:playground` form with the balancing brief, and does not generate any playground HTML itself.'
description: 'Narration case: it assumes an install record for playground@claude-plugins-official, which the eval sandbox does not have, so the with-record branch cannot run here.'
---

/playgrounds:use help me balance the 'Inferno' hero's deck
