---
description: "Plain-language 'walk me through' ruleset request fires github:advise, which emits the exact proposed repository-ruleset call with the one-approval field and, with no doc fetch available, labels from-memory mechanics unverified (SKILL.md 'Refusal branch'). No shell, so nothing can be executed."
tags: [github, advise, outcome, read-only]
max_turns: 20
timeout_seconds: 300
allowed_tools: [Skill, Read]
expected_outcome: "The advise skill fires. The reply walks through a repository ruleset for main on acme/widgets, shows the exact proposed gh api call to repos/acme/widgets/rulesets with required_approving_review_count 1, and marks any mechanics it could not ground in a fetched doc as unverified."
---
Walk me through setting up a ruleset on the main branch of my GitHub repo acme/widgets so that every change has to go through a pull request with one approving review. What's the recommended way to configure it?
