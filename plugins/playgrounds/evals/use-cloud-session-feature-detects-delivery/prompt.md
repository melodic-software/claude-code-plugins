---
description: 'Present-path case: the playground-stub stand-in lists a playground skill whose description matches the upstream one, so Step 1 (no Bash, so the skill-listing fallback) finds it present and Step 4 decides delivery for a session with no local browser.'
tags: ['use']
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Routes generation upstream, then, instead of assuming the upstream flow''s opening step reaches the user, feature-detects the delivery path: offers an Artifact publish or a file send only if the session supports it, and otherwise reports the file path, saying plainly which tiers were unavailable.'
---

/playgrounds:use tune the easing curves on this animation (we are in a cloud session, there is no local browser)
